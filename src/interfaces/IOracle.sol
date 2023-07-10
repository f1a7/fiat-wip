// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IOracle {
    function spot(address token) external returns (uint256);
    function getStatus(address token) external view returns (bool);
}
