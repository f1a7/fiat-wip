// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseHandler} from "../invariant/handlers/BaseHandler.sol";
import {CDMHandler} from "../invariant/handlers/CDMHandler.sol";
import {FIATHandler} from "../invariant/handlers/FIATHandler.sol";
import {CDPVault_TypeAHandler} from "../invariant/handlers/CDPVault_TypeAHandler.sol";
import {TestBase} from "../TestBase.sol";

import {ICDM} from "../../interfaces/ICDM.sol";
import {CDPVaultParams, CDPVaultConfigs} from "../../interfaces/ICDPVault.sol";
import {CDPVaultParams_TypeA} from "../../interfaces/ICDPVault_TypeA_Factory.sol";

import {wmul, WAD, min, max} from "../../utils/Math.sol";
import {PAUSER_ROLE} from "../../utils/Pause.sol";

import {CDM, ACCOUNT_CONFIG_ROLE, getCredit, getDebt} from "../../CDM.sol";
import {CDPVault, VAULT_CONFIG_ROLE, TICK_MANAGER_ROLE, VAULT_UNWINDER_ROLE} from "../../CDPVault.sol";
import {CDPVault_TypeA} from "../../CDPVault_TypeA.sol";
import {CDPVault_TypeA_Factory} from "../../CDPVault_TypeA_Factory.sol";
import {CDPVaultUnwinderFactory} from "../../CDPVaultUnwinder.sol";
import {InterestRateModel} from "../../InterestRateModel.sol";
import {CDPVault_TypeAWrapper, CDPVault_TypeAWrapper_Deployer} from "./CDPVault_TypeAWrapper.sol";

/// @title InvariantTestBase
/// @notice Base test contract with common logic needed by all invariant test contracts.
contract InvariantTestBase is TestBase {

    uint256 constant internal EPSILON = 0.01 ether;

    /// ======== Storage ======== ///

    CDMHandler internal cdmHandler;
    FIATHandler internal fiatHandler;

    error InvariantTestBase__assertGeEpsilon_fail(uint256 a, uint256 b);
    error InvariantTestBase__assertEqEpsilon_fail(uint256 a, uint256 b);

    modifier printReport(BaseHandler handler) {
        {
        _;
        }
        handler.printCallReport();
    }

    function setUp() public override virtual{
        super.setUp();
        filterSenders();
    }

    /// ======== FIAT Invariant Asserts ======== ///
    /*
    FIAT Invariants:
        - Invariant A: sum of balances for all holders is equal to `totalSupply` of `FIAT`
        - Invariant B: conservation of `FIAT` is maintained
    */

    // Invariant A: sum of balances for all holders is equal to `totalSupply` of `FIAT`
    function assert_invariant_FIAT_A() public {
        assertEq(fiat.totalSupply(), fiatHandler.totalUserBalance());
    }

    // Invariant B: conservation of `FIAT` is maintained
    function assert_invariant_FIAT_B() public {
        assertEq(fiatHandler.mintAccumulator(), fiat.totalSupply());
    }

    /// ======== CDM Invariant Asserts ======== ///
    /*
    CDM Invariants:
        - Invariant A: `totalSupply` of `FIAT` is less or equal to `globalDebt`
        - Invariant B: `globalDebt` is less or equal to `globalDebtCeiling`
        - Invariant D: sum of `credit` for all accounts is less or equal to `globalDebt`
        - Invariant F: sum of `debt` for all `Vaults` is less or equal to `globalDebt`
        - Invariant G: sum of `debt` for a `Vault` is less or equal to `debtCeiling`
    */

    // todo: Implement when we enable FIAT minting
    // function invariant_CDM_A() public {
    // }

    // Invariant B: `globalDebt` is less or equal to `globalDebtCeiling`
    function assert_invariant_CDM_B() public {
        assertGe(cdm.globalDebtCeiling(), cdm.globalDebt());
    }

    // Invariant D: sum of `credit` for all accounts is less or equal to `globalDebt`
    function assert_invariant_CDM_D(BaseHandler handler) public {
        uint256 userCount = handler.count("users");
        uint256 totalUserCredit = 0;
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (int256 balance,) = cdm.accounts(user);
            totalUserCredit += getCredit(balance);
        }

        assertGe(cdm.globalDebt(), totalUserCredit);
    }

    // Invariant F: sum of `debt` for all `Vaults` is less or equal to `globalDebt`
    function assert_invariant_CDM_F(BaseHandler handler) public {
        uint256 vaultCount = handler.count("vaults");
        uint256 totalVaultDebt = 0;
        for (uint256 i = 0; i < vaultCount; ++i) {
            address vault = handler.actors("vaults", i);
            (int256 balance, ) = cdm.accounts(vault);
            totalVaultDebt += getDebt(balance);
        }

        assertGe(cdm.globalDebt(), totalVaultDebt);
    }

    // Invariant G: sum of `debt` for a `Vault` is less or equal to `debtCeiling`
    function assert_invariant_CDM_G(BaseHandler handler) public {
        uint256 vaultCount = handler.count("vaults");
        uint256 totalVaultDebt = 0;
        for (uint256 i = 0; i < vaultCount; ++i) {
            address vault = handler.actors("vaults", i);
            (int256 balance, ) = cdm.accounts(vault);
            totalVaultDebt += getDebt(balance);
        }

        assertGe(cdm.globalDebtCeiling(), totalVaultDebt);
    }

    /// ======== CDPVault Invariant Asserts ======== ///

    /*
    CDPVault Invariants:
        - Invariant A: `balanceOf` collateral `token`'s of a `CDPVault_R` is greater or equal to the sum of all the `CDPVault_R`'s `Position`'s `collateral` amounts and the sum of all `cash` balances
        - Invariant B: sum of `normalDebt` of all `Positions` is equal to `totalNormalDebt`
        - Invariant C: `debt` for all `Positions` is greater than `debtFloor` or zero
        - Invariant D: all `Positions` are safe
    */

    // Invariant A: `balanceOf` collateral `token`'s of a `CDPVault_R` is greater or equal to the sum of all the `CDPVault_R`'s `Position`'s `collateral` amounts and the sum of all `cash` balances
    function assert_invariant_CDPVault_A(CDPVault vault, BaseHandler handler) public {
        uint256 totalCollateralBalance = 0;
        uint256 totalCashBalance = 0;

        uint256 userCount = handler.count("users");
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (uint256 collateral, ) = vault.positions(user);
            totalCollateralBalance += collateral;
            totalCashBalance += vault.cash(user);
        }

        uint256 vaultBalance = token.balanceOf(address(vault));

        assertGe(vaultBalance, totalCollateralBalance + totalCashBalance);
    }

    // Invariant B: sum of `normalDebt` of all `Positions` is equal to `totalNormalDebt`
    function assert_invariant_CDPVault_B(CDPVault vault, BaseHandler handler) public {
        uint256 totalNormalDebt = 0;

        uint256 userCount = handler.count("users");
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (, uint256 normalDebt) = vault.positions(user);
            totalNormalDebt += normalDebt;
        }

        assertEq(totalNormalDebt, vault.totalNormalDebt());
    }

    // Invariant C: `debt` for all `Positions` is greater than `debtFloor` or zero
    function assert_invariant_CDPVault_C(CDPVault vault, BaseHandler handler) public {
        (uint128 debtFloor, , ) = vault.vaultConfig();

        uint256 userCount = handler.count("users");
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (, uint256 normalDebt) = vault.positions(user);
            if (normalDebt != 0) {
                assertGe(normalDebt, debtFloor);
            }
        }
    }

    // - Invariant D: all `Positions` are safe
    function assert_invariant_CDPVault_D(CDPVault vault, BaseHandler handler) public {
        uint256 userCount = handler.count("users");
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (uint256 collateral, uint256 normalDebt) = vault.positions(user);
            // ensure that the position is safe (i.e. collateral * liquidationPrice >= normalDebt)
            assertGe(wmul(collateral, liquidationPrice(vault)) ,normalDebt);
        }
    }

    /// ======== Interest Rate Model Invariant Asserts ======== ///

    /*
    Interest Rate Model Invariants:
        - 0 <= `rebateFactor` and `rebateFactor` <= 1 (for all positions)
        - 0 <= `globalRebateFactor` and `globalRebateFactor` <= 1
        - 1 <= `rateAccumulator` (for all positions)
        - 1 <= `rateAccumulator`
        - `rateAccumulator` at block x <= `rateAccumulator` at block y, if x < y and specifically if `rateAccumulator` was updated in between the blocks x and y (for all positions)
        - `rateAccumulator` at block x <= `rateAccumulator` at block y, if x < y and specifically if `rateAccumulator` was updated in between the blocks x and y
        - smallest `rebateFactor` across all positions <= `globalRebateFactor` and `globalRebateFactor` <= largest `rebateFactor` across all positions
        - smallest `rateAccumulator` across all positions <= `rateAccumulator` and `rateAccumulator` <= largest `rateAccumulator` across all positions
        - sum of `rateAccumulator * normalDebt` across all positions <= `rateAccumulator * totalNormalDebt` at any block x
        - sum of `rateAccumulator * normalDebt` across all positions = `rateAccumulator * totalNormalDebt` at any block x in which all positions (and their `rateAccumulator`) were updated
    */

    // - Invariant A: 0 <= `rebateFactor` and `rebateFactor` <= 1 (for all positions)
    function assert_invariant_IRM_A(InterestRateModel irs, BaseHandler handler) public {
        uint256 userCount = handler.count("users");
        
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (InterestRateModel.PositionIRS memory userIRS) = irs.getPositionIRS(user);
            
            assertGe(userIRS.rebateFactor, 0);
            assertLe(userIRS.rebateFactor, WAD);
        }
    }

    // - Invariant B: 0 <= `globalRebateFactor` and `globalRebateFactor` <= 1
    function assert_invariant_IRM_B(InterestRateModel irs) pure public {
        //(InterestRateModel.GlobalIRS memory globalIRS) = irs.getGlobalIRS();
        // assertGe(globalIRS.globalRebateFactor, 0);
        // assertLe(globalIRS.globalRebateFactor, WAD);
    }

    // - Invariant C: 1 <= `rateAccumulator` (for all positions)
    function assert_invariant_IRM_C(InterestRateModel irs, BaseHandler handler) public {
        uint256 userCount = handler.count("users");
        
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (InterestRateModel.PositionIRS memory userIRS) = irs.getPositionIRS(user);
            
            assertGe(userIRS.snapshotRateAccumulator, WAD);
        }
    }

    // - Invariant D: 1 <= `rateAccumulator`
    function assert_invariant_IRM_D(InterestRateModel irs) public {
        (InterestRateModel.GlobalIRS memory globalIRS) = irs.getGlobalIRS();
        assertGe(globalIRS.rateAccumulator, WAD);
    }

    // - Invariant E: `rateAccumulator` at block x <= `rateAccumulator` at block y, if x < y and 
    // specifically if `rateAccumulator` was updated in between the blocks x and y (for all positions)
    function assert_invariant_IRM_E(BaseHandler handler) public {
        uint256 userCount = handler.count("users");
        
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            bytes32 prevValueKey = keccak256(abi.encodePacked(user, "prevRateAccumulator"));
            bytes32 currentValueKey = keccak256(abi.encodePacked(user, "rateAccumulator"));

            uint256 prevRateAccumulator = uint256(handler.valueStorage(prevValueKey));
            uint256 rateAccumulator = uint256(handler.valueStorage(currentValueKey));
            
            assertGe(rateAccumulator, prevRateAccumulator);
        }
    }

    // - Invariant F: `rateAccumulator` at block x <= `rateAccumulator` at block y, if x < y and 
    // specifically if `rateAccumulator` was updated in between the blocks x and y
    function assert_invariant_IRM_F(BaseHandler handler) public {
        bytes32 prevValueKey = bytes32("prevrateAccumulator");
        bytes32 currentValueKey = bytes32("rateAccumulator");

        uint256 prevRateAccumulator = uint256(handler.valueStorage(prevValueKey));
        uint256 rateAccumulator = uint256(handler.valueStorage(currentValueKey));
        
        assertGe(rateAccumulator, prevRateAccumulator);
    }

    // - Invariant G: smallest `rateAccumulator` across all positions <= `rateAccumulator` 
    // and `rateAccumulator` <= largest `rateAccumulator` across all positions
    function assert_invariant_IRM_G(CDPVault vault, BaseHandler handler) view public {
        uint256 userCount = handler.count("users");
        if(userCount == 0) return;
        uint256 minRateAccumulator = type(uint256).max;
        uint256 maxRateAccumulator = 0; 
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (InterestRateModel.PositionIRS memory userIRS) = vault.getPositionIRS(user);
            uint256 userRateAccumulator = userIRS.snapshotRateAccumulator;
            minRateAccumulator = min(minRateAccumulator, userRateAccumulator);
            maxRateAccumulator = max(maxRateAccumulator, userRateAccumulator);
        }
        uint256 rateAccumulator = vault.getGlobalIRS().rateAccumulator;
        assertGeEpsilon(rateAccumulator, minRateAccumulator, EPSILON);
        assertGeEpsilon(maxRateAccumulator, rateAccumulator, EPSILON);
    }
    
    // - Invariant H: sum of `rateAccumulator * normalDebt` across all 
    // positions <= `rateAccumulator * totalNormalDebt` at any block x
    function assert_invariant_IRM_H(CDPVault vault, InterestRateModel irs, BaseHandler handler) view public {
        uint256 userCount = handler.count("users");
        if(userCount == 0) return;
        uint256 sum = 0;
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            (InterestRateModel.PositionIRS memory userIRS) = vault.getPositionIRS(user);
            (,uint256 normalDebt) = vault.positions(user);
            sum += wmul(normalDebt, userIRS.snapshotRateAccumulator);
        }
        uint256 rateAccumulator = irs.getGlobalIRS().rateAccumulator;
        assertGeEpsilon(wmul(rateAccumulator, vault.totalNormalDebt()), sum, EPSILON);
    }

    // - Invariant I: sum of `rateAccumulator * normalDebt` across all positions = `rateAccumulator * totalNormalDebt` 
    // at any block x in which all positions (and their `rateAccumulator`) were updated
    function assert_invariant_IRM_I(CDPVault_TypeAWrapper vault, BaseHandler handler) view public {
        uint256 userCount = handler.count("users");
        if(userCount == 0) return;
        uint256 sum = 0;
        uint64 rateAccumulator;
        for (uint256 i = 0; i < userCount; ++i) {
            address user = handler.actors("users", i);
            // update rateAccumulator
            (rateAccumulator, ,) = vault.virtualIRS(user);
            (, uint256 normalDebt) = vault.positions(user);
            sum += wmul(rateAccumulator, normalDebt);
        }
        (rateAccumulator, ,) = vault.virtualIRS(address(0));
        assertEqEpsilon(wmul(rateAccumulator, vault.totalNormalDebt()), sum ,EPSILON);
    }

    /// ======== Helper Functions ======== ///

    function filterSenders() internal virtual {
        excludeSender(address(cdm));
        excludeSender(address(fiat));
        excludeSender(address(flashlender));
        excludeSender(address(minter));
        excludeSender(address(buffer));
        excludeSender(address(token));
        excludeSender(address(oracle));
    }

    function createCDPVaultWrapper(
        IERC20 token_,
        uint256 debtCeiling,
        uint128 debtFloor,
        uint64 liquidationRatio,
        uint64 liquidationPenalty,
        uint64 liquidationDiscount,
        uint64 targetHealthFactor,
        int64 baseRate,
        uint64 limitOrderFloor,
        uint256 protocolFee
    ) internal returns (CDPVault_TypeAWrapper cdpVaultA) {
        CDPVault_TypeA_Factory factory = new CDPVault_TypeA_Factory(
            new CDPVault_TypeAWrapper_Deployer(),
            address(new CDPVaultUnwinderFactory()),
            address(this),
            address(this),
            address(this)
        );
        cdm.grantRole(ACCOUNT_CONFIG_ROLE, address(factory));

        cdpVaultA = CDPVault_TypeAWrapper(
            factory.create(
                CDPVaultParams({
                    cdm: cdm,
                    oracle: oracle,
                    buffer: buffer,
                    token: token_,
                    tokenScale: 10**IERC20Metadata(address(token_)).decimals(),
                    protocolFee: protocolFee,
                    targetUtilizationRatio: 0,
                    maxUtilizationRatio: uint64(WAD),
                    minInterestRate: uint64(WAD),
                    maxInterestRate: uint64(1000000021919499726),
                    targetInterestRate: uint64(1000000015353288160),
                    rebateRate: uint128(WAD),
                    maxRebate: uint128(WAD)
                }),
                CDPVaultParams_TypeA({
                    liquidationPenalty: liquidationPenalty,
                    liquidationDiscount: liquidationDiscount,
                    targetHealthFactor: targetHealthFactor
                }),
                CDPVaultConfigs({
                    debtFloor: debtFloor,
                    limitOrderFloor: limitOrderFloor,
                    liquidationRatio: liquidationRatio,
                    globalLiquidationRatio: 0,
                    baseRate: baseRate,
                    roleAdmin: address(this),
                    vaultAdmin: address(this),
                    tickManager: address(this),
                    vaultUnwinder: address(this),
                    pauseAdmin: address(this)
                }),
                debtCeiling
            )
        );
    }

    function assertGeEpsilon(uint a, uint b, uint epsilon) pure internal {
        uint lowerBound = (b > epsilon) ? (b - epsilon) : 0;
        if(a<lowerBound)
            revert InvariantTestBase__assertGeEpsilon_fail(a,b);
    }

    function assertEqEpsilon(uint a, uint b, uint epsilon) pure internal {
        uint lowerBound = (b > epsilon) ? (b - epsilon) : 0;
        uint upperBound = b + epsilon;
        if(a<lowerBound || a>upperBound)
            revert InvariantTestBase__assertEqEpsilon_fail(a,b);
    }
}