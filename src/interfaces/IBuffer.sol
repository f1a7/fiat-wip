// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ICDM} from "./ICDM.sol";

interface IBuffer {

    function cdm() external view returns (ICDM);

    function withdrawCredit(address to, uint256 amount) external;

    function bailOut(uint256 amount) external returns (uint256 bailedOut);
}
