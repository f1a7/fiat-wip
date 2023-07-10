// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC1155Holder} from "openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {PRBProxyPlugin} from "prb-proxy/abstracts/PRBProxyPlugin.sol";

/// @title PRBProxyERCPlugin
/// @notice Plugin that implements ERC1155 and ERC721 support for the proxy
contract ERC165Plugin is PRBProxyPlugin, ERC1155Holder, ERC721Holder {
    
    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the list of function signatures of the methods that enable ERC1155 and ERC721 support
    /// @return methods The list of function signatures
    function methodList() external pure override returns (bytes4[] memory methods) {
        methods = new bytes4[](3);
        methods[0] = this.onERC1155Received.selector;
        methods[1] = this.onERC1155BatchReceived.selector;
        methods[2] = this.onERC721Received.selector;
    }
}
