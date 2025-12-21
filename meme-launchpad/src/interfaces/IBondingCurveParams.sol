// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBondingCurveParams {
    struct BondingCurveParams {
        uint256 virtualBNBReserve;    // Virtual BNB reserve
        uint256 virtualTokenReserve;  // Virtual Token reserve
        uint256 k;                    // Constant product k = virtualBNBReserve * virtualTokenReserve
        uint256 availableTokens;      // Available tokens for sale
        uint256 collectedBNB;         // Collected BNB
    }
} 