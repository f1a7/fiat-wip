// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ICDPVaultBase} from "./ICDPVault.sol";

/// @title ICDPVault_TypeA
/// @notice Interface for the CDPVault_TypeA
interface ICDPVault_TypeA is ICDPVaultBase {

    function liquidationConfig() external view returns (uint64, uint64, uint64);

    function liquidatePositions(address[] calldata owners, uint256[] memory repayAmounts) external;
}
