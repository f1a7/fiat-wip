// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {FIAT, MINTER_AND_BURNER_ROLE} from "../../FIAT.sol";

contract TokenUser {
    FIAT public token;

    constructor(FIAT token_) {
        token = token_;
    }

    function doTransferFrom(address from, address to, uint256 amount) public returns (bool) {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint256 amount) public returns (bool) {
        return token.transfer(to, amount);
    }

    function doApprove(address recipient, uint256 amount) public returns (bool) {
        return token.approve(recipient, amount);
    }

    function doAllowance(address owner, address spender) public view returns (uint256) {
        return token.allowance(owner, spender);
    }

    function doBalanceOf(address user) public view returns (uint256) {
        return token.balanceOf(user);
    }

    function doApprove(address spender) public returns (bool) {
        return token.approve(spender, type(uint256).max);
    }

    function doMint(uint256 amount) public {
        token.mint(address(this), amount);
    }

    function doBurn(uint256 amount) public {
        token.burn(address(this), amount);
    }

    function doMint(address to, uint256 amount) public {
        token.mint(to, amount);
    }

    function doBurn(address guy, uint256 amount) public {
        token.burn(guy, amount);
    }
}

contract FIATTest is Test {
    uint256 constant internal initialBalanceThis = 1000;
    uint256 constant internal initialBalanceSender = 100;

    FIAT internal token;
    address internal user1;
    address internal user2;
    address internal self;

    uint256 internal amount = 2;
    uint256 internal fee = 1;
    uint256 internal nonce = 0;
    uint256 internal deadline = 0;
    address internal sender = 0xcfDFCdf4e30Cf2C9CAa2C239677C8d42Ad7D67DE;
    address internal receiver = 0x0D1d31abea2384b0D5add552E3a9b9F66d57e141;
    bytes32 internal r = 0x7b50da6df613cfb1a0065bcc46f5f8d28a4ba45cb58b3737c20a2684d0400dbb;
    bytes32 internal s = 0x1d88b67d2064d5dd67ad175402f5f4aab06d33a8dab185130b73bbbea3f77228;
    uint8 internal v = 27;
    bytes32 internal _r = 0x755be34d2b77a3bd81613f469a14e22bbb27513a396d90277214d5dd1007a5a3;
    bytes32 internal _s = 0x496cc7e9651ae9c7332051c3383cd68c663cc44e957914a4d9c7aa33473368fe;
    uint8 internal _v = 27;

    function setUp() public {
        vm.warp(604411200);
        token = createToken();
        token.mint(address(this), initialBalanceThis);
        token.mint(sender, initialBalanceSender);
        user1 = address(new TokenUser(token));
        user2 = address(new TokenUser(token));
        self = address(this);
    }

    function createToken() internal returns (FIAT) {
        return new FIAT();
    }

    function testSetupPrecondition() public {
        assertEq(token.balanceOf(self), initialBalanceThis);
    }

    function testTransferCost() public {
        token.transfer(address(1), 10);
    }

    function testAllowanceStartsAtZero() public {
        assertEq(token.allowance(user1, user2), 0);
    }

    function testValidTransfers() public {
        uint256 sentAmount = 250;
        token.transfer(user2, sentAmount);
        assertEq(token.balanceOf(user2), sentAmount);
        assertEq(token.balanceOf(self), initialBalanceThis - sentAmount);
    }

    function testFailWrongAccountTransfers() public {
        uint256 sentAmount = 250;
        token.transferFrom(user2, self, sentAmount);
    }

    function testFailInsufficientFundsTransfers() public {
        uint256 sentAmount = 250;
        token.transfer(user1, initialBalanceThis - sentAmount);
        token.transfer(user2, sentAmount + 1);
    }

    function testApproveSetsAllowance() public {
        token.approve(user2, 25);
        assertEq(token.allowance(self, user2), 25);
    }

    function testChargesAmountApproved() public {
        uint256 amountApproved = 20;
        token.approve(user2, amountApproved);
        assertTrue(TokenUser(user2).doTransferFrom(self, user2, amountApproved));
        assertEq(token.balanceOf(self), initialBalanceThis - amountApproved);
    }

    function testFailTransferWithoutApproval() public {
        token.transfer(user1, 50);
        token.transferFrom(user1, self, 1);
    }

    function testFailChargeMoreThanApproved() public {
        token.transfer(user1, 50);
        TokenUser(user1).doApprove(self, 20);
        token.transferFrom(user1, self, 21);
    }

    function testTransferFromSelf() public {
        token.transferFrom(self, user1, 50);
        assertEq(token.balanceOf(user1), 50);
    }

    function testFailTransferFromSelfNonArbitrarySize() public {
        // you shouldn't be able to evade balance checks by transferring
        // to yourself
        token.transferFrom(self, self, token.balanceOf(self) + 1);
    }

    function testMintself() public {
        uint256 mintAmount = 10;
        token.mint(address(this), mintAmount);
        assertEq(token.balanceOf(self), initialBalanceThis + mintAmount);
    }

    function testMintGuy() public {
        uint256 mintAmount = 10;
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);
    }

    function testFailMintGuyNoAuth() public {
        TokenUser(user1).doMint(user2, 10);
    }

    function testMintGuyAuth() public {
        token.grantRole(MINTER_AND_BURNER_ROLE, user1);
        TokenUser(user1).doMint(user2, 10);
    }

    function testBurn() public {
        uint256 burnAmount = 10;
        token.burn(address(this), burnAmount);
        assertEq(token.totalSupply(), initialBalanceThis + initialBalanceSender - burnAmount);
    }

    function testBurnself() public {
        uint256 burnAmount = 10;
        token.burn(address(this), burnAmount);
        assertEq(token.balanceOf(self), initialBalanceThis - burnAmount);
    }

    function testBurnGuyWithTrust() public {
        uint256 burnAmount = 10;
        token.transfer(user1, burnAmount);
        assertEq(token.balanceOf(user1), burnAmount);
        TokenUser(user1).doApprove(self);
        token.burn(user1, burnAmount);
        assertEq(token.balanceOf(user1), 0);
    }

    function testFailBurnGuyNoAuth() public {
        token.transfer(user1, 10);
        TokenUser(user1).doBurn(10);
    }

    function testBurnAuth() public {
        token.transfer(user1, 10);
        token.grantRole(MINTER_AND_BURNER_ROLE, user1);
        TokenUser(user1).doBurn(10);
    }

    function testFailUntrustedTransferFrom() public {
        assertEq(token.allowance(self, user2), 0);
        TokenUser(user1).doTransferFrom(self, user2, 200);
    }

    function testTrusting() public {
        assertEq(token.allowance(self, user2), 0);
        token.approve(user2, type(uint256).max);
        assertEq(token.allowance(self, user2), type(uint256).max);
        token.approve(user2, 0);
        assertEq(token.allowance(self, user2), 0);
    }

    function testTrustedTransferFrom() public {
        token.approve(user1, type(uint256).max);
        TokenUser(user1).doTransferFrom(self, user2, 200);
        assertEq(token.balanceOf(user2), 200);
    }

    function testApproveWillModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1, 1000);
        assertEq(token.allowance(self, user1), 1000);
        TokenUser(user1).doTransferFrom(self, user1, 500);
        assertEq(token.balanceOf(user1), 500);
        assertEq(token.allowance(self, user1), 500);
    }

    function testApproveWillNotModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1, type(uint256).max);
        assertEq(token.allowance(self, user1), type(uint256).max);
        TokenUser(user1).doTransferFrom(self, user1, 1000);
        assertEq(token.balanceOf(user1), 1000);
        assertEq(token.allowance(self, user1), type(uint256).max);
    }

    function testFIATAddress() public {
        // The FIAT address generated by hevm
        // used for signature generation testing
        assertEq(address(token), address(0x0bA14c5a7c7EB53793076a4722Cb0939a235Ac31));
    }

    function testDomain_Separator() public {
        assertEq(token.DOMAIN_SEPARATOR(), 0x4ebb22ecb2ba799f28cc59ed218db473e96a3e5acf8a5d2d27a50ed79715b4cb);
    }

    function testPermit() public {
        assertEq(token.nonces(sender), 0);
        assertEq(token.allowance(sender, receiver), 0);
        token.permit(sender, receiver, type(uint256).max, type(uint256).max, v, r, s);
        assertEq(token.allowance(sender, receiver), type(uint256).max);
        assertEq(token.nonces(sender), 1);
    }

    function testFailPermitAddress0() public {
        v = 0;
        token.permit(address(0), receiver, type(uint256).max, type(uint256).max, v, r, s);
    }

    function testPermitWithExpiry() public {
        assertEq(block.timestamp, 604411200);
        token.permit(sender, receiver, type(uint256).max, 604411200 + 1 hours, _v, _r, _s);
        assertEq(token.allowance(sender, receiver), type(uint256).max);
        assertEq(token.nonces(sender), 1);
    }

    function testFailPermitWithExpiry() public {
        vm.warp(block.timestamp + 2 hours);
        assertEq(block.timestamp, 604411200 + 2 hours);
        token.permit(sender, receiver, type(uint256).max, 1, _v, _r, _s);
    }

    function testFailReplay() public {
        token.permit(sender, receiver, type(uint256).max, type(uint256).max, v, r, s);
        token.permit(sender, receiver, type(uint256).max, type(uint256).max, v, r, s);
    }
}
