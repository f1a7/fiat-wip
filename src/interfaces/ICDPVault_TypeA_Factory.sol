// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CDPVaultParams, CDPVaultConfigs} from "./ICDPVault.sol";
import {ICDM} from "./ICDM.sol";
import {IOracle} from "./IOracle.sol";
import {IBuffer} from "./IBuffer.sol";

struct CDPVaultParams_TypeA {
    uint64 liquidationPenalty;
    uint64 liquidationDiscount;
    uint64 targetHealthFactor;
}

interface ICDPVault_TypeA_Factory {
    function create(
        CDPVaultParams memory params,
        CDPVaultParams_TypeA memory paramsTypeA,
        CDPVaultConfigs memory configs,
        uint256 debtCeiling
    ) external returns (address);

    function getParams() external returns (
        ICDM cdm,
        IOracle oracle,
        IBuffer buffer,
        IERC20 token,
        uint256 tokenScale,
        uint256 protocolFee,
        uint256 utilizationParams,
        uint256 rebateParams,
        address withholder
    );

    function paramsTypeA() external returns (
        uint64 liquidationPenalty,
        uint64 liquidationDiscount,
        uint64 targetHealthFactor
    );

    function unwinderFactory() external returns (address);

}
