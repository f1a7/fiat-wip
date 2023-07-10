// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2} from "forge-std/console2.sol";

import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import {InvariantTestBase} from "../InvariantTestBase.sol";

abstract contract BaseHandler is  CommonBase, StdCheats, StdUtils {

    using Strings for string;

    string DEBUG_ENV = "INVARIANT_DEBUG";

    // Name of the handler, used for debugging
    string public name;

    // Target test contract   
    InvariantTestBase public testContract;

    // Track actors by category
    mapping(string category => address[] userList) public actors;

    // Track if a user has been registered
    mapping(string category => mapping(address user => bool exists)) public registered;

    // Store values for testing changes in state
    mapping(bytes32 key => bytes32 value) public valueStorage;

    // Modifier to restrict access to non-actor accounts
    modifier onlyNonActor(string memory category, address a) {
        if (!registered[category][a]){
            _;
        }
    }

    constructor(string memory name_, InvariantTestBase testContract_) {
        name = name_;
        testContract = testContract_;
        registerContracts();
    }

    // Track when we enter a function
    function trackCallStart(bytes4 sig) internal {
        bytes32 keyStart = keccak256(abi.encodePacked(sig, "start"));
        uint256 enters = uint256(valueStorage[keyStart]);
        valueStorage[keyStart] = bytes32(enters + 1);
    }

    // Track when we exit a function
    function trackCallEnd(bytes4 sig) internal {
        bytes32 keyEnd = keccak256(abi.encodePacked(sig, "end"));
        uint256 exits = uint256(valueStorage[keyEnd]);
        valueStorage[keyEnd] = bytes32(exits + 1);
    }

    // Virtual method to provide method signatures and names for the invariant test contract
    function getTargetSelectors() public pure virtual returns (bytes4[] memory selectors, string[] memory names);

    // Debug function that prints the call report to the console
    function printCallReport() public {
        string memory debugFlag = vm.envOr(DEBUG_ENV, string(""));

        // check if we should print this report
        if(!debugFlag.equal(name) && !debugFlag.equal("*")){
            return;
        }
        
        (bytes4[] memory selectors, string[] memory names) = getTargetSelectors();
        uint256 selectorCount = selectors.length;
        if(selectorCount == 0) return;

        console2.log("-----------------------[CALL REPORT]-----------------------");
        for (uint256 i = 0; i < selectorCount; ++i) {
            printCallCount(names[i], selectors[i]);
        }
    }

    // Print the call count for a given function
    function printCallCount(string memory functionName, bytes4 sig) public view {
        bytes32 keyStart = keccak256(abi.encodePacked(sig, "start"));
        bytes32 keyEnd = keccak256(abi.encodePacked(sig, "end"));

        uint256 enters = uint256(valueStorage[keyStart]);
        uint256 exits = uint256(valueStorage[keyEnd]);
        uint256 accuracy = 0;
        uint256 earlyExit = enters - exits;

        if(enters != 0){
            accuracy = (enters - earlyExit) * 100 / enters;
        }
        
        console2.log(" Function `%s` stats:", functionName);
        console2.log(" Call count %d | Early exits: %d | Accuracy: %d%", 
            enters, 
            earlyExit, 
            accuracy
        );
        console2.log("-----------------------------------------------------------");
    }

    // Helper functions to track actors
    function addActor(string memory category, address a) internal {
        if (!registered[category][a]) {
            actors[category].push(a);
            registered[category][a] = true;
        }
    }

    function removeActor(string memory category, address a) internal {
        if (registered[category][a]) {
            uint256 actorCount = actors[category].length;
            for (uint256 i = 0; i < actorCount; ++i) {
                if (actors[category][i] == a) {
                    actors[category][i] = actors[category][actorCount - 1];
                    actors[category].pop();
                    break;
                }
            }
            registered[category][a] = false;
        }
    }

    function addActors(string memory category, address[] memory a) internal {
        uint256 actorCount = a.length;
        for (uint256 i = 0; i < actorCount; ++i) {
            addActor(category, a[i]);
        }
    }

    function clearActors(string memory category) internal {
        delete actors[category];
    }

    function count(string memory category) public view returns (uint256) {
        return actors[category].length;
    }

    function getRandomActor(string memory category, uint256 seed) public view returns (address) {
        uint256 actorCount = actors[category].length;
        if(actorCount == 0) return address(0);
        
        uint256 index = uint256(keccak256(abi.encodePacked(category, seed))) % actorCount;
        return actors[category][index];
    }

    function registerContracts() virtual internal {
        address[] memory contracts = testContract.getContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            addActor("contracts", contracts[i]);
        }
    }

    // Define common static size add actors functions for convenience
    // For example, addActors("borrower", [borrower1, borrower2]);
    // For dynamic size arrays, use addActors("borrower", borrowerArray);

    // 2 actors
    function addActors(string memory category, address[2] memory a) internal {
        uint256 actorCount = a.length;
        for (uint256 i = 0; i < actorCount; ++i) {
            addActor(category, a[i]);
        }
    }

    // 3 actors
    function addActors(string memory category, address[3] memory a) internal {
        uint256 actorCount = a.length;
        for (uint256 i = 0; i < actorCount; ++i) {
            addActor(category, a[i]);
        }
    }

    // 4 actors
    function addActors(string memory category, address[4] memory a) internal {
        uint256 actorCount = a.length;
        for (uint256 i = 0; i < actorCount; ++i) {
            addActor(category, a[i]);
        }
    }
}
