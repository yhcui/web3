// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DuggeeToken} from "../contracts/DuggeeToken.sol";
import {DuggeeTokenPool} from "../contracts/DuggeeTokenPool.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "./MockERC20.sol";

contract DuggeeTokenPoolTest is Test {
    address wallet = address(0xABCD);
    DuggeeToken duggeeToken;
    MockERC20 token;
    DuggeeTokenPool pool;

    function setUp() public {
        duggeeToken = new DuggeeToken(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3, 1_000_000 * 10**18);
        duggeeToken.transfer(wallet, 500_000 * 10**18);

        token = new MockERC20("USDT Token", "USDT");
        token.mint(wallet, 500_000 * 10**18);

        pool = new DuggeeTokenPool(address(this), address(duggeeToken), address(token));
    }

    function test_FirstAddLiquidity() public {
        // 初始流动性提供者
        vm.startPrank(wallet);
        duggeeToken.approve(address(pool), type(uint256).max);
        token.approve(address(pool), type(uint256).max);

        pool.addLiquidity(1000 * 10**18, 2000 * 10**18, 1900 * 10**18);

        assertEq(pool.totalLiquidity(), Math.sqrt(1000 * 10**18 * 2000 * 10**18), "Total liquidity mismatch");
        assertEq(pool.duggeeReserve(), 1000 * 10**18, "Duggee reserve mismatch");
        assertEq(pool.tokenReserve(), 2000 * 10**18, "Token reserve mismatch");
        assertEq(pool.totalLpTokens(), Math.sqrt(1000 * 10**18 * 2000 * 10**18), "Total LP tokens mismatch");
        assertEq(pool.lpTokens(wallet), Math.sqrt(1000 * 10**18 * 2000 * 10**18), "Wallet LP tokens mismatch");

        assertEq(pool.getPrice(), (2000 * 10**18 * 10**18) / (1000 * 10**18), "Initial price mismatch");

        vm.stopPrank();
    }

    function test_SecondAddLiquidity() public {
        test_FirstAddLiquidity();

        vm.startPrank(wallet);
        duggeeToken.approve(address(pool), type(uint256).max);
        token.approve(address(pool), type(uint256).max);

        pool.addLiquidity(100 * 10**18, 200 * 10**18, 190 * 10**18);

        assertEq(pool.totalLiquidity(), Math.sqrt(1100 * 10**18 * 2200 * 10**18), "Total liquidity mismatch");
        assertEq(pool.duggeeReserve(), 1100 * 10**18, "Duggee reserve mismatch");
        assertEq(pool.tokenReserve(), 2200 * 10**18, "Token reserve mismatch");
        uint256 expectedLpTokens = Math.sqrt(1100 * 10**18 * 2200 * 10**18);
        assertEq(pool.totalLpTokens(), expectedLpTokens, "Total LP tokens mismatch");
        
        assertEq(pool.getPrice(), (2000 * 10**18 * 10**18) / (1000 * 10**18), "Initial price mismatch");
        vm.stopPrank();
    }

    function test_RemoveLiquidity() public {
        test_SecondAddLiquidity();
        uint256 liquidityBefore = pool.lpTokens(wallet);
        vm.startPrank(wallet);
        pool.removeLiquidity(liquidityBefore / 2);
        uint256 liquidityAfter = pool.lpTokens(wallet);
        assertGt(liquidityBefore - liquidityAfter, 0, "LP tokens should ge zero after remove liquidity");
        vm.stopPrank(); 
    }

    function test_Swap() public {
        test_FirstAddLiquidity();

        vm.startPrank(wallet);
        duggeeToken.approve(address(pool), type(uint256).max);
        token.approve(address(pool), type(uint256).max);

        uint256 duggeeBalanceBefore = duggeeToken.balanceOf(wallet);
        uint256 tokenBalanceBefore = token.balanceOf(wallet);

        uint256 fromAmount = 100 * 10**18;
        uint256 feeAmount = fromAmount / 1000;
        uint256 netFromAmount = fromAmount - feeAmount;
        uint256 expectedToAmount = (netFromAmount * 2000 * 10**18) / (1000 * 10**18 + netFromAmount);

        vm.expectEmit(true, true, true, true);
        emit DuggeeTokenPool.Swap(wallet, address(duggeeToken), fromAmount, feeAmount, address(token), expectedToAmount);
        pool.swap(address(duggeeToken), fromAmount, fromAmount / 2);

        uint256 duggeeBalanceAfter = duggeeToken.balanceOf(wallet);
        uint256 tokenBalanceAfter = token.balanceOf(wallet);


        assertEq(duggeeBalanceAfter, duggeeBalanceBefore - 100 * 10**18, "Duggee balance after swap mismatch");
        console.log("Token received:", tokenBalanceAfter - tokenBalanceBefore);

        vm.stopPrank();
    }

    function test_WithdrawFees() public {
        test_Swap();

        uint256 duggeeFeeBalanceBefore = pool.duggeeTokenFeeBalance();
        uint256 tokenFeeBalanceBefore = pool.tokenFeeBalance();
        assertGt(duggeeFeeBalanceBefore + tokenFeeBalanceBefore, 0, "No fees accumulated");

        pool.withdrawFees();

        uint256 duggeeFeeBalance = pool.duggeeTokenFeeBalance();
        uint256 tokenFeeBalance = pool.tokenFeeBalance();

        assertEq(duggeeFeeBalance, 0, "Duggee fee balance should be zero after withdrawal");
        assertEq(tokenFeeBalance, 0, "Token fee balance should be zero after withdrawal");
    }
}