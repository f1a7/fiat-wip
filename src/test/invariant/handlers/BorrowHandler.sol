// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {InterestRateModel} from "../../../InterestRateModel.sol";
import {InvariantTestBase} from "../InvariantTestBase.sol";
import {BaseHandler} from "./BaseHandler.sol";

import {ICDPVaultBase} from "../../../interfaces/ICDPVault.sol";

import {CDPVault} from "../../../CDPVault.sol";
import {CDM, getCreditLine} from "../../../CDM.sol";
import {CDPVault_TypeAWrapper} from "../CDPVault_TypeAWrapper.sol";
import {WAD, min, wdiv, wmul, mul} from "../../../utils/Math.sol";

contract BorrowHandler is BaseHandler {
    uint256 internal constant MAX_BORROW_AMOUNT = 1_000_000 ether;
    uint256 internal constant MAX_SPOT_PRICE = 100 ether;
    uint256 internal constant MIN_SPOT_PRICE = 0.001 ether;
    
    uint256 public immutable creditReserve = 100_000_000_000 ether;
    uint256 public immutable collateralReserve = 100_000_000_000 ether;
    uint256 public immutable minWarp = 0;
    uint256 public immutable maxWarp = 30 days;

    CDM public cdm;
    CDPVault_TypeAWrapper public vault;
    IERC20 public token;

    uint256 public limitOrderPriceIncrement = 0.25 ether;

    mapping (address owner => uint256 limitOrderPrice) activeLimitOrders;

    modifier useTimestamps() {
        vm.warp(testContract.currentTimestamp());
        _;
        testContract.setCurrentTimestamp(block.timestamp);
    }


    function liquidationPrice(ICDPVaultBase vault_) internal returns (uint256) {
        (, uint64 liquidationRatio,) = vault_.vaultConfig();
        return wdiv(vault_.spotPrice(), uint256(liquidationRatio));
    }

    constructor(CDPVault_TypeAWrapper vault_, InvariantTestBase testContract_) BaseHandler("BorrowHandler", testContract_) {
        vault = vault_;
        cdm = CDM(address(vault_.cdm()));
        token = vault.token();
    }

    function getTargetSelectors() public pure virtual override returns (bytes4[] memory selectors, string[] memory names) {
        selectors = new bytes4[](8);
        names = new string[](8);
        selectors[0] = this.borrow.selector;
        names[0] = "borrow";

        selectors[1] = this.partialRepay.selector;
        names[1] = "partialRepay";

        selectors[2] = this.repay.selector;
        names[2] = "repay";

        selectors[3] = this.createLimitOrder.selector;
        names[3] = "createLimitOrder";

        selectors[4] = this.changeLimitOrder.selector;
        names[4] = "changeLimitOrder";

        selectors[5] = this.cancelLimitOrder.selector;
        names[5] = "cancelLimitOrder";

        selectors[6] = this.changeSpotPrice.selector;
        names[6] = "changeSpotPrice";

        selectors[7] = this.changeBaseRate.selector;
        names[7] = "changeBaseRate";
    }

    // Account (with or without existing position) deposits collateral and increases debt
    function borrow(uint256 amount, uint256 warpAmount) public useTimestamps {
        trackCallStart(msg.sig);

        // register sender as a user
        addActor("users", msg.sender);

        (uint128 debtFloor,,) = vault.vaultConfig();
        amount = bound(amount, debtFloor + 1, MAX_BORROW_AMOUNT);

        // compute approximate collateral amount needed to borrow `amount`
        uint256 deltaCollateral = wdiv(amount, liquidationPrice(vault));
        deltaCollateral = bound(deltaCollateral, 0, token.balanceOf(address(this)));

        // deposit collateral if needed
        if(vault.cash(msg.sender) < deltaCollateral) {
            token.approve(address(vault), deltaCollateral);
            vault.deposit(msg.sender, deltaCollateral);
        }

        int256 deltaDebt = vault.getMaximumDebtForCollateral(msg.sender, int256(deltaCollateral));
        if (deltaDebt > 0){
            vm.prank(msg.sender);
            vault.modifyCollateralAndDebt(msg.sender, msg.sender, msg.sender, int256(deltaCollateral), deltaDebt);
        }

        _trackRateAccumulator(msg.sender);
        
        warpInterval(warpAmount);

        trackCallEnd(msg.sig);
    }

    // Partially repays debt and withdraws collateral
    function partialRepay(uint256 userSeed, uint256 percent) public useTimestamps {
        trackCallStart(msg.sig);

        percent = bound(percent, 1, 99);

        address owner = getRandomActor("users", userSeed);
        
        if(owner == address(0)) return;

        cdm.modifyPermission(address(vault), true);
        
        (, uint256 normalDebt) = vault.positions(owner);
        if(normalDebt == 0) return;
        
        (uint128 debtFloor, , ) = vault.vaultConfig();

        uint256 amount = (normalDebt * percent) / 100;
        (int256 balance, uint256 debtCeiling) = cdm.accounts(address(this));
        amount = bound(amount, 0, getCreditLine(balance, debtCeiling));

        // full replay if we are below debt floor
        if(int256(normalDebt - amount) < int256(int128(debtFloor))) amount = normalDebt;
        vault.modifyCollateralAndDebt(owner, owner, address(this), 0, -int256(amount));

        _trackRateAccumulator(owner);

        trackCallEnd(msg.sig);
    }

    // Fully repay debt and withdraws collateral
    function repay(uint256 userSeed) public useTimestamps {
        trackCallStart(msg.sig);

        // same as partialRepay, but 100%
        // users are removed from the list if they have no debt
        address owner = getRandomActor("users", userSeed);
        if(owner == address(0)) return;

        cdm.modifyPermission(address(vault), true);
        
        (, uint256 normalDebt) = vault.positions(owner);

        if(normalDebt == 0) return;
        
        (int256 balance, uint256 debtCeiling) = cdm.accounts(address(this));
        normalDebt = bound(normalDebt, 0, getCreditLine(balance, debtCeiling));
        vault.modifyCollateralAndDebt(owner, owner, address(this), 0, -int256(normalDebt));

        _trackRateAccumulator(owner);

        trackCallEnd(msg.sig);
    }

    // User with existing position creates limit order
    function createLimitOrder(uint256 userSeed, uint128 priceTickSeed) public useTimestamps {
        trackCallStart(msg.sig);

        uint256 limitPriceTick = _generateTickPrice(priceTickSeed);
        
        address owner = getRandomActor("users", userSeed);
        if(owner == address(0)) return;

        (, uint256 normalDebt) = vault.positions(owner);
        if (normalDebt <= vault.limitOrderFloor()) return;
        if(registered["limitOrder"][owner]) return;

        activeLimitOrders[owner] = limitPriceTick;
        addActor("limitOrder", owner);

        vm.prank(owner);
        vault.createLimitOrder(limitPriceTick);

        _trackRateAccumulator(owner);

        trackCallEnd(msg.sig);
    }

    // User with existing limit order changes order’s tick price
    function changeLimitOrder(uint256 limitOrderSeed, uint128 priceTickSeed) public useTimestamps {
        trackCallStart(msg.sig);

        address owner = getRandomActor("limitOrder", limitOrderSeed);
        if(owner == address(0)) return;

        // cancel the existing order
        uint256 priceTick = vault.limitOrders(uint256(uint160(owner)));
        if (priceTick != 0){
            vm.prank(owner);
            vault.cancelLimitOrder();
        }

        (, uint256 normalDebt) = vault.positions(owner);
        // can't create new limit order because of limit order floor
        if (normalDebt <= vault.limitOrderFloor()){
            _trackRateAccumulator(owner);
            removeActor("limitOrder", owner);
            delete activeLimitOrders[owner];
            return;
        }

        // bound the new limit order price
        uint256 limitPriceTick = _generateTickPrice(priceTickSeed);
        // create the new order
        activeLimitOrders[owner] = limitPriceTick;

        vm.prank(owner);
        vault.createLimitOrder(limitPriceTick);

        _trackRateAccumulator(owner);

        trackCallEnd(msg.sig);
    }

    // User with existing limit order cancels the order
    function cancelLimitOrder(uint256 limitOrderSeed) public useTimestamps {
        trackCallStart(msg.sig);

        address owner = getRandomActor("limitOrder", limitOrderSeed);
        if(owner == address(0)) return;

        // cancel the existing order
        uint256 priceTick = vault.limitOrders(uint256(uint160(owner)));
        if (priceTick != 0){
            vm.prank(owner);
            vault.cancelLimitOrder();
        }
        _trackRateAccumulator(owner);

        removeActor("limitOrder", owner);
        delete activeLimitOrders[owner];

        trackCallEnd(msg.sig);
    }

    // Governance updates the base interest rate
    function changeBaseRate(uint256 /*baseRate*/) public {
        trackCallStart(msg.sig);
        // baseRate = bound (baseRate, 1, WAD);
        // vault.setParameter("baseRate", baseRate);
        trackCallEnd(msg.sig);
    }

    // Oracle updates the collateral spot price
    function changeSpotPrice(uint256 price) public {
        trackCallStart(msg.sig);

        price = bound(price, MIN_SPOT_PRICE, MAX_SPOT_PRICE);
        testContract.setOraclePrice(price);

        trackCallEnd(msg.sig);
    }

    /// ======== Helper Functions ======== ///

    function warpInterval(uint256 warpAmount_) public useTimestamps {
        warpAmount_ = bound(warpAmount_, minWarp, maxWarp);
        vm.warp(block.timestamp + warpAmount_);
    }

    // Helper function to create placeholder price ticks
    function createPriceTicks() public {
        uint256 price = 100 ether;
        uint256 nextPrice = 0;
        while(price >= 1 ether) {
            vault.addLimitPriceTick(price, nextPrice);
            nextPrice = price;
            price -= limitOrderPriceIncrement;
        }
    }

    // Track the current and the previous rate accumulator for a user
    function _trackRateAccumulator(address user) private {
        bytes32 prevValueKey = keccak256(abi.encodePacked(user, "prevRateAccumulator"));
        bytes32 currentValueKey = keccak256(abi.encodePacked(user, "rateAccumulator"));
        InterestRateModel.PositionIRS memory posIRS = vault.getPositionIRS(user);
        valueStorage[prevValueKey] = valueStorage[currentValueKey];
        valueStorage[currentValueKey] = bytes32(uint256(posIRS.snapshotRateAccumulator));

        _trackrateAccumulator();
    }

    // Track the current and the previous global rate accumulator
    function _trackrateAccumulator() public {
        InterestRateModel.GlobalIRS memory globalIRS = vault.getGlobalIRS();
        bytes32 prevValueKey = bytes32("prevrateAccumulator");
        bytes32 currentValueKey = bytes32("rateAccumulator");
        valueStorage[prevValueKey] = valueStorage[currentValueKey];
        valueStorage[currentValueKey] = bytes32(uint256(globalIRS.rateAccumulator));
    }

    // Generate the tick price for a limit order based on the seed
    function _generateTickPrice(uint256 priceTickSeed) private view returns (uint256){
        return 1 ether + bound(priceTickSeed , 0, 99 ether / limitOrderPriceIncrement) * limitOrderPriceIncrement;
    }
}