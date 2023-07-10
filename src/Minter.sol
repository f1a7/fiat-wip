// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AccessControl} from "openzeppelin/contracts/access/AccessControl.sol";

import {ICDM} from "./interfaces/ICDM.sol";
import {IFIAT} from "./interfaces/IFIAT.sol";
import {IMinter} from "./interfaces/IMinter.sol";

import {Pause, PAUSER_ROLE} from "./utils/Pause.sol";

/// @title Minter (FIAT Mint)
/// @notice The canonical mint for FIAT (Fixed Income Asset Token),
/// where users can redeem their internal credit for FIAT
contract Minter is IMinter, AccessControl, Pause {

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The CDM contract
    ICDM public immutable override cdm;
    /// @notice FIAT token
    IFIAT public immutable override fiat;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Enter(address indexed user, uint256 amount);
    event Exit(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(ICDM cdm_, IFIAT fiat_, address roleAdmin, address pauseAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, roleAdmin);
        _grantRole(PAUSER_ROLE, pauseAdmin);

        cdm = cdm_;
        fiat = fiat_;
    }

    /*//////////////////////////////////////////////////////////////
                       CREDIT AND FIAT REDEMPTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Redeems FIAT for internal credit
    /// @dev User has to set allowance for Minter to burn FIAT
    /// @param user Address of the user
    /// @param amount Amount of FIAT to be redeemed for internal credit [wad]
    function enter(address user, uint256 amount) external override {
        cdm.modifyBalance(address(this), user, amount);
        fiat.burn(msg.sender, amount);
        emit Enter(user, amount);
    }

    /// @notice Redeems internal credit for FIAT
    /// @dev User has to grant the delegate of transferring credit to Minter
    /// @param user Address of the user
    /// @param amount Amount of credit to be redeemed for FIAT [wad]
    function exit(address user, uint256 amount) external override whenNotPaused {
        cdm.modifyBalance(msg.sender, address(this), amount);
        fiat.mint(user, amount);
        emit Exit(user, amount);
    }
}
