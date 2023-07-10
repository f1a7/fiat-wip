// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./InvariantTestBase.sol";
import {TICK_MANAGER_ROLE} from "../../CDPVault.sol";
import {BorrowHandler} from "./handlers/BorrowHandler.sol";

import {CDPVault_TypeAWrapper} from "./CDPVault_TypeAWrapper.sol";

/// @title BorrowInvariantTest
contract BorrowInvariantTest is InvariantTestBase {
    CDPVault_TypeAWrapper internal cdpVaultR;
    BorrowHandler internal borrowHandler;

    /// ======== Setup ======== ///

    function setUp() public virtual override {
        super.setUp();

        cdpVaultR = createCDPVaultWrapper({
            token_: token, 
            debtCeiling: initialGlobalDebtCeiling, 
            debtFloor: 100 ether, 
            liquidationRatio: 1.25 ether, 
            liquidationPenalty: 1.0 ether,
            liquidationDiscount: 1.0 ether, 
            targetHealthFactor: 1.05 ether, 
            baseRate: 1 ether,
            limitOrderFloor: 1 ether,
            protocolFee: 0.01 ether
        });

        borrowHandler = new BorrowHandler(cdpVaultR, this);
        deal(
            address(token),
            address(borrowHandler),
            borrowHandler.collateralReserve() + borrowHandler.creditReserve()
        );

        // prepare price ticks
        cdpVaultR.grantRole(TICK_MANAGER_ROLE, address(borrowHandler));
        borrowHandler.createPriceTicks();

        _setupCreditVault();

        excludeSender(address(cdpVaultR));
        excludeSender(address(borrowHandler));

        vm.label({account: address(cdpVaultR), newLabel: "CDPVault_TypeA"});
        vm.label({
            account: address(borrowHandler),
            newLabel: "BorrowHandler"
        });

        (bytes4[] memory selectors, ) = borrowHandler.getTargetSelectors();
        targetSelector(
            FuzzSelector({
                addr: address(borrowHandler),
                selectors: selectors
            })
        );

        targetContract(address(borrowHandler));
    }

    // deploy a reserve vault and create credit for the borrow handler
    function _setupCreditVault() private {
        CDPVault_TypeA creditVault = createCDPVaultWrapper({
            token_: token, 
            debtCeiling: borrowHandler.creditReserve(), 
            debtFloor: 100 ether, 
            liquidationRatio: 1.25 ether, 
            liquidationPenalty: 1.0 ether,
            liquidationDiscount: 1.0 ether, 
            targetHealthFactor: 1.05 ether, 
            baseRate: 1 ether,
            limitOrderFloor: 1 ether,
            protocolFee: 0.01 ether
        });

        // increase the global debt ceiling
        setGlobalDebtCeiling(
            initialGlobalDebtCeiling + borrowHandler.creditReserve()
        );

        vm.startPrank(address(borrowHandler));
        token.approve(address(creditVault), borrowHandler.creditReserve());
        creditVault.deposit(
            address(borrowHandler),
            borrowHandler.creditReserve()
        );
        int256 debt = int256(wmul(liquidationPrice(creditVault), borrowHandler.creditReserve()));
        creditVault.modifyCollateralAndDebt(
            address(borrowHandler),
            address(borrowHandler),
            address(borrowHandler),
            int256(borrowHandler.creditReserve()),
            debt
        );
        vm.stopPrank();
    }

    // function test_invariant_G() public {
    //     vm.prank(0xC584190C9dA82E71a25e9313068030055600d0E2);
    //     borrowHandler.borrow(861565241390895385757504174504823555731211889829, 6456);
    //     vm.prank(0x00000000000000008B323A1BE83Aa4EF5FE74238);
    //     borrowHandler.createLimitOrder(94179920690290737231757078903665764886, 340282366920938463463374607431768211453);
    //     vm.prank(0xbe83b7003Ba9405509aAaaB216f8fE386EcD266B);
    //     borrowHandler.borrow(24517123240803142394960042352050417874802154896047648494295256460487544537088, 259406665);
    //     vm.prank(0x203428bfeF9D2f8Ba3f7f34273e516dFAB9B9974);
    //     borrowHandler.changeSpotPrice(1);
    //     vm.prank(0x9c396404a9387E0912806BAD0FfF856682025895);
    //     borrowHandler.changeLimitOrder(27053182806635289012055184468145415373298232839357620001418888668604307457548, 0);
    //     this.invariant_IRM_G();
    // }

    // function test_invariant_H() public {
    //     vm.prank(0x00000000000000000000000000000000000020CD);
    //     borrowHandler.repay(1);
    //     vm.prank(0x0000000000000000000000000000000000000030);
    //     borrowHandler.partialRepay(115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
    //     vm.prank(0x3376d08F48afd13A329717C3C51c209838143019);
    //     borrowHandler.borrow(1401615756594913315959738715854458956182906429944499978376, 111511584078685565807274364324706580485807);
    //     vm.prank(0x00000000000000000000000000000000000055e4);
    //     borrowHandler.borrow(37599234650753362243451188619309533798705208281645224423, 1);
    //     vm.prank(0x0000000000000000000000000000000000000799);
    //     borrowHandler.cancelLimitOrder(111919148320163936029094370791792864502250201084275266812419015644);
    //     vm.prank(0xB21D9594767bfc54dcfE01858989614357b1C3d5);
    //     borrowHandler.repay(2532);
    //     vm.prank(0x00000000000000000000000000000000000019A9);
    //     borrowHandler.borrow(2, 1);
    //     vm.prank(0x0000000000000000000000000000000000002c25);
    //     borrowHandler.partialRepay(5280071275615563280715, 2);
    //     this.invariant_IRM_H();
    // }
    // function test_invariant_H2() public {
    //     vm.prank(0x0000000000000000000000000e92596FD6290000);
    //     borrowHandler.borrow(0, 699805231951989708717008175195254525397756664861391946505597128686392690749);
    //     vm.prank(0xBde8f31BBCFc81D04EE3518c7DD1602d7425C83D);
    //     borrowHandler.borrow(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
    //     this.invariant_IRM_H();
    // }
    // function test_invariant_H3() public {
    //     vm.prank(0x00000000000000000000000417C5E1fBdDfe0000);
    //     borrowHandler.borrow(17311800172708325519734628882101729165784709693632351769484939242885451117, 31835877663223426417835742420);
    //     this.invariant_IRM_H();
    // }

    /// ======== CDPVault Invariant Tests ======== ///

    function invariant_CDPVault_R_A() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_CDPVault_A(cdpVaultR, borrowHandler);
    }

    function invariant_CDPVault_R_B() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_CDPVault_B(cdpVaultR, borrowHandler);
    }

    function invariant_CDPVault_R_C() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_CDPVault_C(cdpVaultR, borrowHandler);
    }

    /// ======== Interest Rate Model Invariant Tests ======== ///

    function invariant_IRM_A() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_A(cdpVaultR, borrowHandler);
    }

    function invariant_IRM_B() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_B(cdpVaultR);
    }

    function invariant_IRM_C() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_C(cdpVaultR, borrowHandler);
    }

    function invariant_IRM_D() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_D(cdpVaultR);
    }

    function invariant_IRM_E() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_E(borrowHandler);
    }

    function invariant_IRM_F() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_F(borrowHandler);
    }

    function invariant_IRM_G() external useCurrentTimestamp printReport(borrowHandler) {
        assert_invariant_IRM_G(cdpVaultR, borrowHandler);
    }

    // function invariant_IRM_H() external useCurrentTimestamp printReport(borrowHandler) {
    //     assert_invariant_IRM_H(cdpVaultR, borrowHandler);
    // }
    
    // function invariant_IRM_I() external useCurrentTimestamp {
    //     assert_invariant_IRM_I(cdpVaultR, cdpVaultR, borrowHandler);
    // }

    // function invariant_IRM_J() external useCurrentTimestamp {
    //     assert_invariant_IRM_J(cdpVaultR, cdpVaultR, borrowHandler);
    // }
}
