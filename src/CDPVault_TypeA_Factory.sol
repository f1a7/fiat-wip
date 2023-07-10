// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AccessControl} from "openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBuffer} from "./interfaces/IBuffer.sol";
import {ICDM} from "./interfaces/ICDM.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {CDPVaultParams, CDPVaultConfigs} from "./interfaces/ICDPVault.sol";
import {ICDPVault_TypeA_Factory, CDPVaultParams_TypeA} from "./interfaces/ICDPVault_TypeA_Factory.sol";
import {ICDPVault_TypeA_Deployer} from "./interfaces/ICDPVault_TypeA_Deployer.sol";

import {Pause, PAUSER_ROLE} from "./utils/Pause.sol";
import {WAD} from "./utils/Math.sol";

import {VAULT_CONFIG_ROLE, TICK_MANAGER_ROLE, VAULT_UNWINDER_ROLE} from "./CDPVault.sol";
import {CDPVault_TypeA} from "./CDPVault_TypeA.sol";
import {CreditWithholder} from "./CreditWithholder.sol";

// Authenticated Roles
bytes32 constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

contract CDPVault_TypeA_Factory is ICDPVault_TypeA_Factory, AccessControl, Pause {

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    CDPVaultParams_TypeA public paramsTypeA;
    CDPVaultParams internal params;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deployer contract responsible for housing CDPVault_TypeA bytecode
    ICDPVault_TypeA_Deployer public immutable deployer;
    /// @notice Vault Unwinder Factory contract
    address public immutable unwinderFactory;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CreateVault(address indexed vault, address indexed token, address indexed creator);

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(
        ICDPVault_TypeA_Deployer deployer_,
        address unwinderFactory_,
        address roleAdmin,
        address deployerAdmin,
        address pauseAdmin
    ) {
        deployer = deployer_;
        unwinderFactory = unwinderFactory_;
        _grantRole(DEFAULT_ADMIN_ROLE, roleAdmin);
        _grantRole(DEPLOYER_ROLE, deployerAdmin);
        _grantRole(PAUSER_ROLE, pauseAdmin);
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function create(
        CDPVaultParams memory params_,
        CDPVaultParams_TypeA memory paramsTypeA_,
        CDPVaultConfigs memory configs,
        uint256 debtCeiling
    ) external whenNotPaused returns (address) {
        params = params_;
        paramsTypeA = paramsTypeA_;

        CDPVault_TypeA vault = CDPVault_TypeA(deployer.deploy());
        vault.setUp(unwinderFactory);

        delete params;
        delete paramsTypeA;

        vault.grantRole(VAULT_CONFIG_ROLE, address(this));

        // set parameters
        vault.setParameter("debtFloor", configs.debtFloor);
        vault.setParameter("limitOrderFloor", configs.limitOrderFloor);
        vault.setParameter("liquidationRatio", configs.liquidationRatio);
        vault.setParameter("globalLiquidationRatio", configs.globalLiquidationRatio);
        vault.setParameter("baseRate", uint256(uint64(configs.baseRate)));

        // set roles
        vault.grantRole(VAULT_CONFIG_ROLE, configs.vaultAdmin);
        vault.grantRole(TICK_MANAGER_ROLE, configs.tickManager);
        vault.grantRole(VAULT_UNWINDER_ROLE, configs.vaultUnwinder);
        vault.grantRole(PAUSER_ROLE, configs.pauseAdmin);
        vault.grantRole(DEFAULT_ADMIN_ROLE, configs.roleAdmin);

        // revoke factory roles
        vault.revokeRole(VAULT_CONFIG_ROLE, address(this));
        vault.revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        // reverts if debtCeiling is set and msg.sender does not have the DEPLOYER_ROLE
        if (debtCeiling > 0) {
            _checkRole(DEPLOYER_ROLE);
            params_.cdm.setParameter(address(vault), "debtCeiling", debtCeiling);
        }

        emit CreateVault(address(vault), address(params_.token), msg.sender);

        return address(vault);
    }

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
    ) {
        utilizationParams =
            uint256(params.targetUtilizationRatio) | (uint256(params.maxUtilizationRatio) << 64) | (uint256(params.minInterestRate - WAD) << 128) |
            (uint256(params.maxInterestRate - WAD) << 168) | (uint256(params.targetInterestRate - WAD) << 208);
        rebateParams = uint256(params.rebateRate) | (uint256(params.maxRebate) << 128);
        withholder = address(new CreditWithholder(params.cdm, address(unwinderFactory), msg.sender));
        return (
            params.cdm,
            params.oracle,
            params.buffer,
            params.token,
            params.tokenScale,
            params.protocolFee,
            utilizationParams,
            rebateParams,
            withholder
        );
    }

}

contract CDPVault_TypeA_Deployer is ICDPVault_TypeA_Deployer {

    function deploy() external returns (address vault) {
        vault = address(new CDPVault_TypeA(msg.sender));
    }
}
