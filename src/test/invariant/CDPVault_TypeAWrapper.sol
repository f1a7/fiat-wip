// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICDM} from "../../interfaces/ICDM.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {IBuffer} from "../../interfaces/IBuffer.sol";
import {ICDPVault_TypeA_Deployer} from "../../interfaces/ICDPVault_TypeA_Deployer.sol";
import {CDPVault_TypeA} from "../../CDPVault_TypeA.sol";
import {CDM, getCreditLine} from "../../CDM.sol";

import {wmul, wdiv, max, min, add, mul, WAD} from "../../utils/Math.sol";

contract CDPVault_TypeAWrapper is CDPVault_TypeA {
    
    constructor(address factory) CDPVault_TypeA(factory) {}

    function getMaximumDebtForCollateral(address owner, int256 deltaCollateral) public returns (int256 deltaNormalDebt) {
        Position memory position = positions[owner];
        if(deltaCollateral < 0 ) deltaCollateral = min(deltaCollateral, -int256(position.collateral));
        uint64 rateAccumulatorBuffer = 1.1e18;

        (int256 vaultBalance, uint256 vaultDebtCeiling) = cdm.accounts(address(this));
        uint256 positionDebtCeiling = wmul(
            add(position.collateral, deltaCollateral), 
            liquidationPrice()
        );

        uint256 vaultDebtCapacity = min(getCreditLine(vaultBalance, vaultDebtCeiling), cdm.globalDebtCeiling() - cdm.globalDebt());
        (uint64 rateAccumulator, uint256 accruedRebate,) = virtualIRS(owner);
        rateAccumulator = uint64(wmul(rateAccumulator, rateAccumulatorBuffer));
        uint256 positionDebtCapacity = 0;
        {
        uint256 debt = wmul(position.normalDebt, rateAccumulator) - accruedRebate;
        if(positionDebtCeiling >= debt){
            positionDebtCapacity = positionDebtCeiling - debt;
        }
        }
        deltaNormalDebt = int256(wdiv(min(vaultDebtCapacity, positionDebtCapacity), rateAccumulator));
        int256 newPositionDebt = int256(positions[owner].normalDebt) + deltaNormalDebt;
        // if we are below the debt floor cancel the deltaDebt
        if(newPositionDebt > 0 && newPositionDebt < int256(int128(vaultConfig.debtFloor))){
            deltaNormalDebt = 0;
        }
    }

    function liquidationPrice() internal returns (uint256) {
        return wdiv(spotPrice(), uint256(vaultConfig.liquidationRatio));
    }
}

contract CDPVault_TypeAWrapper_Deployer is ICDPVault_TypeA_Deployer {
    function deploy() external returns (address vault) {
        vault = address(new CDPVault_TypeAWrapper(msg.sender));
    }
}
