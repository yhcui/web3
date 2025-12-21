// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMEMECore.sol";

interface IMEMEHelper {
    error InvalidCurve();
    error InsufficientLiquidity();
    error ZeroAmount();
    error ZeroAddress();

    function calculateTokenAmountOut(uint256 bnbIn, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    function calculateRequiredBNB(uint256 tokenOut, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    function calculateTokenAmountOutWithFee(uint256 bnbIn, IMEMECore.BondingCurveParams memory curve, uint256 feeRate) external pure returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB);

    function calculateBNBAmountOut(uint256 tokenIn, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    function calculateBNBAmountOutWithFee(uint256 tokenIn, IMEMECore.BondingCurveParams memory curve, uint256 feeRate) external pure returns (uint256 netBNB, uint256 feeBNB);

    function addLiquidityV2(address token, uint256 bnbAmount, uint256 tokenAmount) external payable returns (uint256 liquidity);

    function getPrice(IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    function getPairAddress(address token) external view returns (address);
} 