// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {max, min, add, sub} from "../../../utils/Math.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {InvariantTestBase} from "../InvariantTestBase.sol";
import {FIAT, MINTER_AND_BURNER_ROLE} from "../../../FIAT.sol";

contract FIATHandler is BaseHandler {
    FIAT public fiat;

    uint256 public totalSupply = uint256(type(int256).max);
    uint256 public mintAccumulator = 0;

    constructor(address fiat_, InvariantTestBase testContract_) BaseHandler("FIATHandler", testContract_) {
        fiat = FIAT(fiat_);
    }

    function getTargetSelectors() public pure virtual override returns(bytes4[] memory selectors, string[] memory names) {
        selectors = new bytes4[](7);
        names = new string[](7);
        
        selectors[0] = this.mint.selector;
        names[0] = "mint";

        selectors[1] = this.burn.selector;
        names[1] = "burn";

        selectors[2] = this.transferFrom.selector;
        names[2] = "transferFrom";

        selectors[3] = this.transfer.selector;
        names[3] = "transfer";

        selectors[4] = this.approve.selector;
        names[4] = "approve";

        selectors[5] = this.increaseAllowance.selector;
        names[5] = "increaseAllowance";

        selectors[6] = this.decreaseAllowance.selector;
        names[6] = "decreaseAllowance";
    }

    // Mint tokens to a user, amount is capped by the total supply
    function mint(uint256 amount) public {
        trackCallStart(msg.sig);

        addActor("users", msg.sender);

        // avoid overflow
        amount = bound(amount, 0, totalSupply - mintAccumulator);

        mintAccumulator = add(mintAccumulator, int256(amount));

        fiat.mint(msg.sender, amount);

        trackCallEnd(msg.sig);
    }

    // Burn tokens from a user, amount is capped by the user's balance and
    // and the allowance of the caller
    function burn(address from, uint256 amount) public {
        trackCallStart(msg.sig);

        if (from == address(0)) return;
        addActor("users", from);

        uint256 balance = fiat.balanceOf(from);
        uint256 allowance = fiat.allowance(from, msg.sender);
        amount = bound(amount, 0, min(balance, allowance));

        fiat.grantRole(MINTER_AND_BURNER_ROLE, msg.sender);
        vm.prank(msg.sender);
        fiat.burn(from, amount);

        mintAccumulator = sub(mintAccumulator, int256(amount));

        trackCallEnd(msg.sig);
    }

    // Transfer tokens from one user to another, amount is capped
    // by the user's balance and the allowance of the caller
    function transferFrom(address from, address to, uint256 amount) public {
        trackCallStart(msg.sig);

        if (from == address(0) || to == address(0)) return;

        addActors("users", [from, to]);

        uint256 balance = fiat.balanceOf(from);
        uint256 allowance = fiat.allowance(from, msg.sender);
        amount = bound(amount, 0, min(balance, allowance));

        vm.prank(msg.sender);
        fiat.transferFrom(from, to, amount);

        trackCallEnd(msg.sig);
    }

    // Transfer tokens to another user, amount is capped by the caller's balance
    function transfer(address to, uint256 amount) public {
        trackCallStart(msg.sig);

        if (to == address(0)) return;
        addActors("users", [msg.sender, to]);
        amount = bound(amount, 0, fiat.balanceOf(msg.sender));

        vm.prank(msg.sender);
        fiat.transfer(to, amount);

        trackCallEnd(msg.sig);
    }

    /// Approve a spender to transfer tokens on behalf of the caller, `spender` cannot
    // be the zero address
    function approve(address spender, uint256 amount) public {
        trackCallStart(msg.sig);

        if (spender == address(0)) return;
        addActors("users", [msg.sender, spender]);

        vm.prank(msg.sender);
        fiat.approve(spender, amount);

        trackCallEnd(msg.sig);
    }

    // Increases the allowance granted to `spender` by the caller, `spender` cannot
    // be the zero address
    function increaseAllowance(address spender, uint256 amount) public {
        trackCallStart(msg.sig);

        if (spender == address(0)) return;
        addActors("users", [msg.sender, spender]);

        vm.prank(msg.sender);
        fiat.increaseAllowance(spender, amount);

        trackCallEnd(msg.sig);
    }

    // Decrease the allowance granted to `spender` by the caller, `spender` cannot
    // be the zero address
    function decreaseAllowance(address spender, uint256 amount) public {
        trackCallStart(msg.sig);

        if (spender == address(0)) return;
        addActors("users", [msg.sender, spender]);

        amount = bound(amount, 0, fiat.allowance(msg.sender, spender));

        vm.prank(msg.sender);
        fiat.decreaseAllowance(spender, amount);

        trackCallEnd(msg.sig);
    }

    // Helper function that computes the total balance of all users
    // The total balance of all users
    // This function should be excluded from the invariant target selectors
    function totalUserBalance() public view returns (uint256) {
        uint256 total = 0;
        uint256 count_ = count("users");
        for (uint256 i = 0; i < count_; ++i) {
            total = add(total, int256(fiat.balanceOf(actors["users"][i])));
        }
        return total;
    }
}
