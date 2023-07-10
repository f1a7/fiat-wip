// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {ACCOUNT_CONFIG_ROLE} from "../../CDM.sol";
import {MINTER_AND_BURNER_ROLE} from "../../FIAT.sol";
import "./InvariantTestBase.sol";
/// @title CDMInvariantTest
/// @notice CDM invariant tests 
contract CDMInvariantTest is InvariantTestBase{
    /// ======== Setup ======== ///
    function setUp() public override virtual{
        super.setUp();

        fiatHandler = new FIATHandler(address(fiat), this);
        fiat.grantRole(0x00, address(fiatHandler));
        fiat.grantRole(MINTER_AND_BURNER_ROLE, address(fiatHandler));
        // setup fiat handler selectors
        bytes4[] memory fiatHandlerSelectors = new bytes4[](7);
        fiatHandlerSelectors[0] = FIATHandler.mint.selector;
        fiatHandlerSelectors[1] = FIATHandler.burn.selector;
        fiatHandlerSelectors[2] = FIATHandler.transferFrom.selector;
        fiatHandlerSelectors[3] = FIATHandler.transfer.selector;
        fiatHandlerSelectors[4] = FIATHandler.approve.selector;
        fiatHandlerSelectors[5] = FIATHandler.increaseAllowance.selector;
        fiatHandlerSelectors[6] = FIATHandler.decreaseAllowance.selector;
        targetSelector(FuzzSelector({addr: address(fiatHandler), selectors: fiatHandlerSelectors}));
        cdmHandler = new CDMHandler(address(cdm), this);

        cdm.grantRole(ACCOUNT_CONFIG_ROLE, address(cdmHandler));
        // exclude the handlers from the invariants
        excludeSender(address(fiatHandler));
        excludeSender(address(cdmHandler));
        // label the handlers
        vm.label({ account: address(fiatHandler), newLabel: "FIATHandler" });
        vm.label({ account: address(cdmHandler), newLabel: "CDMHandler" });
        targetContract(address(fiatHandler));
        targetContract(address(cdmHandler));
    }

    /// ======== FIAT Invariant Tests ======== ///

    function invariant_FIAT_A() external useCurrentTimestamp printReport(fiatHandler) { assert_invariant_FIAT_A(); }
    function invariant_FIAT_B() external useCurrentTimestamp printReport(fiatHandler) { assert_invariant_FIAT_B(); }

    /// ======== CDM Invariant Tests ======== ///
    
    //function invariant_CDM_A() external useCurrentTimestamp { assert_invariant_CDM_A(); }
    function invariant_CDM_B() external useCurrentTimestamp printReport(cdmHandler) { assert_invariant_CDM_B(); }
    function invariant_CDM_D() external useCurrentTimestamp printReport(cdmHandler) { assert_invariant_CDM_D(cdmHandler); }
    function invariant_CDM_F() external useCurrentTimestamp printReport(cdmHandler) { assert_invariant_CDM_F(cdmHandler); }
    function invariant_CDM_G() external useCurrentTimestamp printReport(cdmHandler) { assert_invariant_CDM_G(cdmHandler); }
}