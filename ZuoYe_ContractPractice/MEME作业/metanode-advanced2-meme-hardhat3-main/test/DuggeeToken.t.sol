// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DuggeeToken} from "../contracts/DuggeeToken.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract DuggeeTokenTest is Test {
    address wallet = address(0xABCD);
    DuggeeToken duggeeToken;

    function setUp() public {
        duggeeToken = new DuggeeToken(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3, 1_000_000 * 10**18);
        duggeeToken.transfer(wallet, 500_000 * 10**18);
    }

    function test_InitialSupply() public view {
        uint256 totalSupply = duggeeToken.totalSupply();
        require(totalSupply == 1_000_000 * 10**18, "Initial supply should be 1,000,000 DUG");
    }

    function test_Tax() public {
        uint256 walletBalanceBefore = duggeeToken.balanceOf(wallet);

        address user1 = address(0x1);
        vm.expectEmit(true, true, true, true);
        emit DuggeeToken.TransferTaxed(wallet, user1, (1000 * 10**18) * 95 / 100, (1000 * 10**18) * 5 / 100);
        vm.prank(wallet);
        duggeeToken.transfer(user1, 1000 * 10**18);

        uint256 walletBalanceAfter = duggeeToken.balanceOf(wallet);
        assertEq(walletBalanceBefore - 1000 * 10**18, walletBalanceAfter, "Wallet balance should decrease by 1000 DUG plus tax");

        uint256 user1Balance = duggeeToken.balanceOf(user1);
        assertEq(user1Balance, (1000 * 10**18) * 95 / 100, "User1 should receive 995 DUG after 5% tax");
    }

    function test_maxTxAmount() public {
        vm.prank(wallet);
        vm.expectRevert("more than max tx amount");
        duggeeToken.transfer(address(0x1), 2000 * 10**18);
    }

    function test_dailyTxLimit() public {
        vm.startPrank(wallet);
        for (uint8 i = 0; i < 10; i++) {
            duggeeToken.transfer(address(0x1), 500 * 10**18);
        }

        vm.expectRevert("exceeds daily transaction limit");
        duggeeToken.transfer(address(0x1), 500 * 10**18);
        vm.stopPrank();
    }
}

