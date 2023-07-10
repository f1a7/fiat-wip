// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseHandler} from "./BaseHandler.sol";
import {InvariantTestBase} from "../InvariantTestBase.sol";

import {WAD, wmul, mul, max, min, add} from "../../../utils/Math.sol";
import {CDM} from "../../../CDM.sol";
import {CDPVault_TypeAWrapper} from "../CDPVault_TypeAWrapper.sol";

contract CDPVault_TypeAHandler is BaseHandler {
    CDPVault_TypeAWrapper public vault;
    CDM public cdm;
    IERC20 public token;

    uint256 public tokenReserve = 1_000_000_000 ether;

    constructor(InvariantTestBase testContract_, CDPVault_TypeAWrapper vault_) BaseHandler("CDPVault_TypeAHandler", testContract_) {
        vault = vault_;
        cdm = CDM(address(vault.cdm()));
        token = vault.token();
    }

    function deposit(address to, uint256 amount) onlyNonActor("contracts", to) public {
        trackCallStart(msg.sig);

        address from = msg.sender;
        addActors("users", [from, to]);
        uint256 balance = token.balanceOf(msg.sender);

        if (amount > balance) {
            uint256 dealAmount = min(amount - balance, token.balanceOf(address(this)));
            token.transfer(from, dealAmount);
        }

        amount = bound(amount, 0, token.balanceOf(from));
        vm.startPrank(from);
        token.approve(address(vault), amount);
        vault.deposit(to, amount);
        vm.stopPrank();

        trackCallEnd(msg.sig);
    }

    function withdraw(address to, uint256 amount) onlyNonActor("contracts", to) public {
        trackCallStart(msg.sig);

        address from = msg.sender;
        if (to == address(0)) return;
        addActors("users", [from, to]);
        amount = bound(amount, 0, vault.cash(from));
        vm.prank(from);
        vault.withdraw(to, amount);

        trackCallEnd(msg.sig);
    }

    function modifyCollateralAndDebt(
        address collateralizer,
        address creditor,
        int256 deltaCollateral,
        int256 deltaNormalDebt
    ) onlyNonActor("contracts", collateralizer) onlyNonActor("contracts", creditor) public {
        trackCallStart(msg.sig);

        address user = msg.sender;
        if (collateralizer == address(0) || creditor == address(0)) return;
        addActors("users", [user, collateralizer, creditor]);

        // ensure permissions are set
        _setupPermissions(user, collateralizer, creditor);

        // deposit collateral if needed
        {
        uint256 collateralBalance = vault.cash(collateralizer);
        if (deltaCollateral > 0 && int256(collateralBalance) < deltaCollateral) {
           deposit(collateralizer, uint256(deltaCollateral - int256(collateralBalance)));
        }
        }

        (uint256 collateral, uint256 normalDebt) = vault.positions(user);
        deltaCollateral = bound(deltaCollateral, -int256(collateral), int256(vault.cash(collateralizer)));
        int256 maxDebt = vault.getMaximumDebtForCollateral(user, int256(deltaCollateral));
        deltaNormalDebt = bound(deltaNormalDebt, -int256(normalDebt), int256(maxDebt));

        (uint128 debtFloor, ,) = vault.vaultConfig();
        // ensure debt floor is respected
        if(int256(normalDebt) + deltaNormalDebt < int256(uint256(debtFloor))) deltaNormalDebt = 0;

        vm.startPrank(msg.sender);
        vault.modifyCollateralAndDebt(user, collateralizer, creditor, deltaCollateral, deltaNormalDebt);
        vm.stopPrank();

        trackCallEnd(msg.sig);
    }

    function getTargetSelectors() public pure virtual override returns(bytes4[] memory selectors, string[] memory names) {
        selectors = new bytes4[](3);
        names = new string[](3);

        selectors[0] = this.deposit.selector;
        names[0] = "deposit";

        selectors[1] = this.withdraw.selector;
        names[1] = "withdraw";

        selectors[2] = this.modifyCollateralAndDebt.selector;
        names[2] = "modifyCollateralAndDebt";
    }

    function _setupPermissions(address user, address collateralizer, address creditor) internal {
        vm.prank(collateralizer);
        vault.modifyPermission(user, true);

        vm.startPrank(creditor);
        vault.modifyPermission(user, true);
        cdm.modifyPermission(address(vault), true);
        vm.stopPrank();
    }
}
