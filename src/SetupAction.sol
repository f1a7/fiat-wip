// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IPRBProxy} from "prb-proxy/interfaces/IPRBProxy.sol";
import {IPRBProxyAnnex} from "prb-proxy/interfaces/IPRBProxyAnnex.sol";
import {IPRBProxyPlugin} from "prb-proxy/interfaces/IPRBProxyPlugin.sol";
import {PRBProxyStorage} from "prb-proxy/abstracts/PRBProxyStorage.sol";

import {BaseAction} from "./BaseAction.sol";

/// @title SetupAction
/// @notice This action enables a proxy to install a set of plugins and delegate call into a target
/// contract in one transaction. Together with `deployAndExecute` in `PRBProxyFactory`, deploying a proxy,
/// initializing a proxy and executing a transaction can be bundled into one transaction.
contract SetupAction is PRBProxyStorage, BaseAction {

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    IPRBProxyAnnex immutable proxyAnnex;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(IPRBProxyAnnex proxyAnnex_) {
        proxyAnnex = proxyAnnex_;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Installs a set of plugins for a proxy and delegate calls into the
    /// provided target contract by forwarding data.
    /// @dev Called in the context of the proxy and should not be called directly
    /// @param plugins The plugins to install on the proxy
    /// @param target The target contract to delegate call
    /// @param data The data to forward to the target contract
    function installAndExecute(IPRBProxyPlugin[] calldata plugins, address target, bytes calldata data) external {
        // install plugins on the proxy
        uint256 totalPlugins = plugins.length;
        for (uint256 i; i < totalPlugins; ) {
            _delegateCall(
                address(proxyAnnex),
                abi.encodeWithSelector(IPRBProxyAnnex.installPlugin.selector, plugins[i])
            );

            unchecked {
                ++i;
            }
        }

        // execute the first transaction
        _delegateCall(
            address(this),
            abi.encodeWithSelector(IPRBProxy.execute.selector, target, data)
        );

    }

}
