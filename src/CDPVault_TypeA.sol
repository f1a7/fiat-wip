// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ICDPVault_TypeA} from "./interfaces/ICDPVault_TypeA.sol";
import {ICDPVault_TypeA_Factory} from "./interfaces/ICDPVault_TypeA_Factory.sol";

import {WAD, max, min, wmul, wdiv} from "./utils/Math.sol";

import {CDPVault, calculateNormalDebt, calculateDebt} from "./CDPVault.sol";

/// @title CDPVault_TypeA
/// @notice A CDP-style vault for depositing collateral and drawing credit against it.
/// TypeA vaults are liquidated permissionlessly by selling as much collateral of an unsafe position until it meets
/// a targeted collateralization ratio again. Any shortfall from liquidation not being able to be recovered
/// by selling the available collateral is covered by the global Buffer or the Credit Delegators.
contract CDPVault_TypeA is CDPVault, ICDPVault_TypeA {

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    struct LiquidationConfig {
        // is subtracted from the `repayAmount` to avoid profitable self liquidations [wad]
        // defined as: 1 - penalty (e.g. `liquidationPenalty` = 0.95 is a 5% penalty)
        uint64 liquidationPenalty;
        // is subtracted from the `spotPrice` of the collateral to provide incentive to liquidate unsafe positions [wad]
        // defined as: 1 - discount (e.g. `liquidationDiscount` = 0.95 is a 5% discount)
        uint64 liquidationDiscount;
        // the targeted health factor an unsafe position has to meet after being partially liquidation [wad]
        // defined as: > 1.0 (e.g. `targetHealthFactor` = 1.05, `liquidationRatio` = 125% provides a cushion of 6.25%) 
        uint64 targetHealthFactor;
    }
    /// @notice Liquidation configuration
    LiquidationConfig public liquidationConfig;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event LiquidatePosition(
        address indexed position,
        uint256 collateralReleased,
        uint256 normalDebtRepaid,
        address indexed liquidator
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error CDPVault__liquidatePosition_notUnsafe();
    error CDPVault__liquidatePositions_argLengthMismatch();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(address factory) CDPVault(factory) {}

    function setUp(address unwinderFactory) public override {
        super.setUp(unwinderFactory);
        (
            uint64 liquidationPenalty,
            uint64 liquidationDiscount,
            uint64 targetHealthFactor
        ) = ICDPVault_TypeA_Factory(msg.sender).paramsTypeA();

        liquidationConfig.liquidationPenalty = liquidationPenalty;
        liquidationConfig.liquidationDiscount = liquidationDiscount;
        liquidationConfig.targetHealthFactor = targetHealthFactor;
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    // avoid stack-too-deep in `liquidatePositions`
    struct LiquidationCache {
        uint256 spotPrice;
        uint64 rateAccumulator;
        // cached state variables to be evaluated after processing all liquidations
        GlobalIRS globalIRS;
        uint256 totalNormalDebt;
        uint256 accruedBadDebt;
        uint256 accruedInterest;
        uint256 totalRepayAmount;
        uint256 totalCashAmount;
        // to avoid stack-too-deep in `_liquidatePosition`
        uint128 claimedRebate;
        uint128 accruedRebate;
        // cached state variables
        uint256 debtFloor;
        uint256 liquidationRatio;
        uint256 targetHealthFactor;
        uint256 liquidationPenalty;
        uint256 liquidationDiscount;
    }

    /// @notice Liquidates an unsafe position (see `liquidatePositions`)
    function _liquidatePosition(
        LiquidationCache memory cache,
        address owner,
        uint256 repayAmount
    ) internal returns (LiquidationCache memory) {
        Position memory position = positions[owner];

        // update the accrued rebate of the position up until now and snapshot the current rate accumulator
        PositionIRS memory positionIRS = getPositionIRS(owner);
        positionIRS.accruedRebate = _calculateAccruedRebate(positionIRS, cache.rateAccumulator, position.normalDebt);
        cache.accruedRebate = positionIRS.accruedRebate;
        positionIRS.snapshotRateAccumulator = cache.rateAccumulator;

        // calculate the normal debt of the position that can be recovered
        uint256 normalDebtToRecover;
        {
        uint256 debt = calculateDebt(position.normalDebt, cache.rateAccumulator, positionIRS.accruedRebate);
        uint256 collateralValue = wdiv(
            wmul(position.collateral, cache.spotPrice), cache.liquidationRatio
        );

        // verify that the position is indeed unsafe
        if (cache.spotPrice == 0 || _isCollateralized(
            debt, position.collateral, cache.spotPrice, cache.liquidationRatio
        )) revert CDPVault__liquidatePosition_notUnsafe();

        // limit the repay amount if it exceeds the net debt of the position
        repayAmount = min(repayAmount, wdiv(debt, cache.liquidationPenalty));

        // calculate the max. amount of debt we can recover with the position's collateral in order to get
        // the health factor back to the target health factor
        uint256 maxDebtToRecover = wdiv(
            wmul(cache.targetHealthFactor, debt) - collateralValue,
            wmul(cache.targetHealthFactor, cache.liquidationPenalty)
                - wdiv(
                    WAD,
                    wmul(cache.liquidationRatio, cache.liquidationDiscount)
                )
        );

        // limit the repay amount by max. amount of debt to recover
        repayAmount = min(repayAmount, maxDebtToRecover);

        // calculate the rebate amount to claim for the position and deduct it from the accrued rebate of the position
        (cache.claimedRebate, positionIRS.accruedRebate) = _calculateRebateClaim(
            repayAmount, debt, positionIRS.accruedRebate
        );

        // adjust the normalized debt we are able to recover
        normalDebtToRecover = calculateNormalDebt(
            wmul(repayAmount, cache.liquidationPenalty),
            cache.rateAccumulator,
            cache.claimedRebate
        );
        }

        // calculate how much collateral we have to release in exchange for the repay amount
        uint256 collateralToRelease = wdiv(
            repayAmount,
            wmul(cache.spotPrice, cache.liquidationDiscount)
        );

        // there may be not enough collateral to sell to cover the entire debt when applying the spot price
        // in that case we sell all the collateral and recover as much debt as possible
        if (
            position.normalDebt < normalDebtToRecover
            || position.normalDebt - normalDebtToRecover < cache.debtFloor
            || collateralToRelease > position.collateral
        ) {
            (collateralToRelease, normalDebtToRecover) = (position.collateral, position.normalDebt);
            cache.claimedRebate = cache.accruedRebate;
            // we apply the liquidation penalty only to the accrued bad debt and not to the repay amount as this
            // would reduce the amount of debt we can recover
            // the liquidation penalty is effectively paid by the credit delegators or the buffer respectively
            // for the latter it's netted out since it goes to the buffer as well
            repayAmount = wmul(collateralToRelease, wmul(cache.spotPrice, cache.liquidationDiscount));
            uint256 debt = calculateDebt(position.normalDebt, cache.rateAccumulator, cache.claimedRebate);
            uint256 netRepayAmount = wmul(repayAmount, cache.liquidationPenalty);
            if (debt < netRepayAmount) cache.accruedInterest += netRepayAmount - debt;
            else cache.accruedBadDebt += debt - netRepayAmount;
        }


        // reorder stack
        uint128 claimedRebate = uint128(cache.claimedRebate);

        // update the limit order (removed if below limit order floor), and update the interest rate states
        uint256 accruedInterest;
        (cache.globalIRS, accruedInterest) = _updateLimitOrderAndPositionIRSAndCalculateGlobalIRS(
            owner,
            cache.globalIRS,
            positionIRS,
            cache.totalNormalDebt,
            position.normalDebt,
            -int256(normalDebtToRecover),
            claimedRebate,
            0
        );

        // repay the position's debt balance and release the bought collateral amount
        _modifyPosition(
            owner,
            position,
            positionIRS,
            -int256(collateralToRelease),
            -int256(normalDebtToRecover),
            cache.totalNormalDebt
        );

        // update the total normalized debt, total repaid debt, released collateral and accrued interest amounts 
        cache.totalNormalDebt -= normalDebtToRecover;
        cache.totalRepayAmount += repayAmount;
        cache.totalCashAmount += collateralToRelease;
        cache.accruedInterest += accruedInterest;

        emit LiquidatePosition(owner, collateralToRelease, normalDebtToRecover, msg.sender);

        return cache;
    }

    /// @notice Liquidates multiple unsafe positions by selling as much collateral as required to cover the debt in
    /// order to make the positions safe again. The collateral can be bought at a discount (`liquidationDiscount`) to
    /// the current spot price. The liquidator has to provide the amount he wants repay or sell (`repayAmounts`) for
    /// each position. From that repay amount a penalty (`liquidationPenalty`) is subtracted to mitigate against
    /// profitable self liquidations. If the available collateral of a position is not sufficient to cover the debt
    /// the vault is able to apply for a bail out from the global Buffer, any residual bad debt not covered by the 
    /// Buffer will be attributed to the credit delegators.
    /// @dev The liquidator has to approve the vault to transfer the sum of `repayAmounts`.
    /// @param owners Owners of the positions to liquidate
    /// @param repayAmounts Amounts the liquidator wants to repay for each position [wad]
    function liquidatePositions(address[] calldata owners, uint256[] memory repayAmounts) external whenNotPaused {
        if (owners.length != repayAmounts.length) revert CDPVault__liquidatePositions_argLengthMismatch();
        GlobalIRS memory globalIRS = getGlobalIRS();

        LiquidationCache memory cache;
        cache.spotPrice = spotPrice();
        cache.rateAccumulator = _calculateRateAccumulator(globalIRS);
        cache.globalIRS = globalIRS;
        cache.totalNormalDebt = totalNormalDebt;
        cache.liquidationRatio = vaultConfig.liquidationRatio;
        cache.debtFloor = vaultConfig.debtFloor;
        cache.targetHealthFactor = liquidationConfig.targetHealthFactor;
        cache.liquidationPenalty = liquidationConfig.liquidationPenalty;
        cache.liquidationDiscount = liquidationConfig.liquidationDiscount;

        for (uint256 i; i < owners.length; ) {
            if (!(owners[i] == address(0) || repayAmounts[i] == 0)) {
                cache = _liquidatePosition(cache, owners[i], repayAmounts[i]);
            }
            unchecked { ++i; }
        }

        // check if the vault entered emergency mode, store the new cached global interest rate state and collect fees
        _checkForEmergencyModeAndStoreGlobalIRSAndCollectFees(
            cache.globalIRS,
            cache.accruedInterest + wmul(cache.totalRepayAmount, WAD - cache.liquidationPenalty),
            cache.totalNormalDebt,
            cache.spotPrice,
            vaultConfig.globalLiquidationRatio
        );
   
        // store the new cached total normalized debt
        totalNormalDebt = cache.totalNormalDebt;

        // transfer the repay amount from the liquidator to the vault
        cdm.modifyBalance(msg.sender, address(this), cache.totalRepayAmount);

        // transfer the cash amount from the vault to the liquidator
        cash[msg.sender] += cache.totalCashAmount;

        // try absorbing any accrued bad debt by applying for a bail out and mark down the residual bad debt
        if (cache.accruedBadDebt != 0) {
            // apply for a bail out from the Buffer
            buffer.bailOut(cache.accruedBadDebt); 
        }
    }
}
