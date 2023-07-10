// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPause {

    function pausedAt() external view returns (uint256);

    function pause() external;

    function unpause() external;
}