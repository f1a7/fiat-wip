// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ICDM} from "./ICDM.sol";
import {IFIAT} from "./IFIAT.sol";

interface IMinter {
    function cdm() external view returns (ICDM);

    function fiat() external view returns (IFIAT);

    function enter(address user, uint256 amount) external;

    function exit(address user, uint256 amount) external;
}
