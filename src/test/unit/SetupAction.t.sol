// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {ERC1155Holder} from "openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


import {IPRBProxy} from "prb-proxy/interfaces/IPRBProxy.sol";
import {IPRBProxyAnnex} from "prb-proxy/interfaces/IPRBProxyAnnex.sol";
import {IPRBProxyPlugin} from "prb-proxy/interfaces/IPRBProxyPlugin.sol";
import {PRBProxy} from "prb-proxy/PRBProxy.sol";
import {PRBProxyAnnex} from "prb-proxy/PRBProxyAnnex.sol";
import {PRBProxyRegistry} from "prb-proxy/PRBProxyRegistry.sol";
import {PRBProxyPlugin} from "prb-proxy/abstracts/PRBProxyPlugin.sol";

import {SetupAction} from "../../SetupAction.sol";
import {ERC165Plugin} from "../../ERC165Plugin.sol";

contract EmptyPlugin is PRBProxyPlugin {
    function methodList() external pure override returns (bytes4[] memory) {}
}

contract SetupActionTest is Test {
    PRBProxyRegistry public registry;
    SetupAction public setupAction;

    function getNextProxyAddress() public view returns (address) {
        bytes32 creationBytecodeHash = keccak256(type(PRBProxy).creationCode);
        bytes32 salt = keccak256(abi.encode(tx.origin, registry.nextSeeds(tx.origin)));
        return computeCreate2Address(salt, creationBytecodeHash, address(registry));
    }

    function prepareDeployParams(address mockTarget) public returns (bytes memory proxyData) {
        IPRBProxyPlugin[] memory plugins = new IPRBProxyPlugin[](1);
        plugins[0] = new ERC165Plugin();

        bytes memory targetData = abi.encodeWithSignature("mockAction()");

        proxyData = abi.encodeWithSelector(
            SetupAction.installAndExecute.selector,
            plugins,
            mockTarget,
            targetData
        );
    }

    function setUp() public {
        registry = new PRBProxyRegistry();
        setupAction = new SetupAction(new PRBProxyAnnex());
    }

    function test_deploy() public {
        assertTrue(address(setupAction) != address(0));
    }

    function test_deployAndExecuteFor() public {
        // pseudo random user address
        address user = address(0x1);
        address precomputedAddress = getNextProxyAddress();

        address target = address(0x2);
        bytes memory deployData = prepareDeployParams(target);
        vm.mockCall(target, abi.encodeWithSignature("mockAction()"), abi.encodeWithSignature("mockAction()"));
        (IPRBProxy proxy, ) = registry.deployAndExecuteFor(user, address(setupAction), deployData);

        assertEq(address(proxy), precomputedAddress);
    }

    function test_deployAndExecuteFor_revertOnIncompletePlugin() public {
        IPRBProxyPlugin[] memory plugins = new IPRBProxyPlugin[](1);
        plugins[0] = new EmptyPlugin();

        bytes memory deployData = abi.encodeWithSelector(
            SetupAction.installAndExecute.selector,
            plugins,
            address(0),
            ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(IPRBProxyAnnex.PRBProxy_NoPluginMethods.selector, address(plugins[0]))
        );
        registry.deployAndExecuteFor(address(0x1), address(setupAction), deployData);
    }

    function test_deployAndExecuteFor_revertOnInvalidPlugin() public {
        IPRBProxyPlugin[] memory plugins = new IPRBProxyPlugin[](1);
        plugins[0] = IPRBProxyPlugin(address(0x12345));

        bytes memory deployData = abi.encodeWithSelector(
            SetupAction.installAndExecute.selector,
            plugins,
            address(0),
            ""
        );

        vm.expectRevert();
        registry.deployAndExecuteFor(address(0x1), address(setupAction), deployData);
    }

    function test_plugin_onERC1155Received() public {
        // pseudo random user address
        address user = address(0x2);

        address target = address(0x3);
        bytes memory deployData = prepareDeployParams(target);
        vm.mockCall(target, abi.encodeWithSignature("mockAction()"), abi.encodeWithSignature("mockAction()"));

        (IPRBProxy proxy, ) = registry.deployAndExecuteFor(user, address(setupAction), deployData);

        // call the plugin function with dummy data
        (bool success, bytes memory result) = address(proxy).call(
            abi.encodeWithSelector(ERC1155Holder.onERC1155Received.selector, address(0), address(0), 0, 0, "")
        );

        assertTrue(success);
        assertEq(ERC1155Holder.onERC1155Received.selector, bytes4(result));
    }

    function test_plugin_onERC1155BatchReceived() public {
        // pseudo random user address
        address user = address(0x2);
        address target = address(0x3);
        bytes memory deployData = prepareDeployParams(target);
        vm.mockCall(target, abi.encodeWithSignature("mockAction()"), abi.encodeWithSignature("mockAction()"));

        (IPRBProxy proxy, ) = registry.deployAndExecuteFor(user, address(setupAction), deployData);

        // call the plugin function with dummy data
        (bool success, bytes memory result) = address(proxy).call(
            abi.encodeWithSelector(ERC1155Holder.onERC1155BatchReceived.selector, address(0), address(0), [0], [0], "")
        );

        assertTrue(success);
        assertEq(ERC1155Holder.onERC1155BatchReceived.selector, bytes4(result));
    }

    function test_plugin_onERC721Received() public {
        // pseudo random user address
        address user = address(0x2);

        address target = address(0x3);
        bytes memory deployData = prepareDeployParams(target);
        vm.mockCall(target, abi.encodeWithSignature("mockAction()"), abi.encodeWithSignature("mockAction()"));

        (IPRBProxy proxy, ) = registry.deployAndExecuteFor(user, address(setupAction), deployData);

        // call the plugin function with dummy data
        (bool success, bytes memory result) = address(proxy).call(
            abi.encodeWithSelector(ERC721Holder.onERC721Received.selector, address(0), address(0), 0, "")
        );

        assertTrue(success);
        assertEq(ERC721Holder.onERC721Received.selector, bytes4(result));
    }
}
