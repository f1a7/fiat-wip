// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ICDPVault} from "./ICDPVault.sol";
import {ICDPVaultUnwinder} from "./ICDPVaultUnwinder.sol";

interface ICDPVaultUnwinderFactory {

    function deployVaultUnwinder(ICDPVault vault) external returns (ICDPVaultUnwinder unwinder);
}