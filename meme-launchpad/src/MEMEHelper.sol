// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from"@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMEMEHelper} from "./interfaces/IMEMEHelper.sol";
import {IMEMECore} from "./interfaces/IMEMECore.sol";
import {IPancakeFactory} from "./interfaces/IPancakeFactory.sol";
import {IPancakeRouter02} from "./interfaces/IPancakeRouter02.sol";
import {IPancakePair} from "./interfaces/IPancakePair.sol";

/**
 * @title MEMEHelper
 * @dev Utility contract for bonding curve calculations and PancakeSwap integration
 */
contract MEMEHelper is IMEMEHelper, AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant CORE_ROLE = keccak256("CORE_ROLE");
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    address public immutable PANCAKE_V2_ROUTER;
    address public immutable WBNB;

    constructor(address _admin, address _router, address _wbnb) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CORE_ROLE, _admin);
        if (_router == address(0)) revert ZeroAddress();
        if (_wbnb == address(0)) revert ZeroAddress();
        PANCAKE_V2_ROUTER = _router;
        WBNB = _wbnb;
    }

    /**
     * @dev Add liquidity to PancakeSwap V2
     * @param token Token address
     * @param bnbAmount BNB amount to add
     * @param tokenAmount Token amount to add
     * @return liquidity Amount of LP tokens received
     */
    function addLiquidityV2(
        address token,
        uint256 bnbAmount,
        uint256 tokenAmount
    ) external payable onlyRole(CORE_ROLE) returns (uint256 liquidity) {
        if (bnbAmount == 0 || tokenAmount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        IERC20(token).approve(PANCAKE_V2_ROUTER, tokenAmount);

        (,, liquidity) = IPancakeRouter02(PANCAKE_V2_ROUTER).addLiquidityETH{value: bnbAmount}(
            token,
            tokenAmount,
            tokenAmount * 95 / 100, // 5% slippage protection
            bnbAmount * 95 / 100,   // 5% slippage protection
            block.timestamp + 300, // 5 minutes expiration time
            true
        );
    }

    /**
     * @dev Get PancakeSwap pair address for token-WBNB
     * @param token Token address
     * @return pair Pair contract address
     */
    function getPairAddress(address token) external view override returns (address pair) {
        address factory = IPancakeRouter02(PANCAKE_V2_ROUTER).factory();
        pair = IPancakeFactory(factory).getPair(token, WBNB);
        if (pair == address(0)) {
            (address token0, address token1) = token < WBNB
                ? (token, WBNB)
                : (WBNB, token);

            pair = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                factory,
                                keccak256(abi.encodePacked(token0, token1)),
                                IPancakeFactory(factory).INIT_CODE_HASH() // init code hash
                            )
                        )
                    )
                )
            );
        }
    }

    /**
     * @dev Estimate LP token amount after adding liquidity
     * @param token Token address
     * @param bnbAmount BNB amount to add
     * @param tokenAmount Token amount to add
     * @return Estimated LP token amount
     */
    function estimateLPTokens(
        address token,
        uint256 bnbAmount,
        uint256 tokenAmount
    ) external view returns (uint256) {
        address pair = IPancakeFactory(IPancakeRouter02(PANCAKE_V2_ROUTER).factory()).getPair(token, WBNB);
        if (pair == address(0)) {
            // If it's the first time adding liquidity, LP amount approximately equals sqrt(bnbAmount * tokenAmount)
            uint256 product = bnbAmount * tokenAmount;
            uint256 liquidity = sqrt(product);

            if (liquidity > MINIMUM_LIQUIDITY) {
                return liquidity - MINIMUM_LIQUIDITY;
            } else {
                return 0;
            }
        } else {
            // If pool already exists, need to calculate based on existing reserves
            // Simplified handling here, returns 0 indicating more complex calculation needed
            return 0;
        }
    }

    /**
     * @dev Calculate token output amount for given BNB input using bonding curve
     * @param bnbIn BNB input amount
     * @param curve Bonding curve parameters
     * @return tokenOut Token output amount
     */
    function calculateTokenAmountOut(
        uint256 bnbIn,
        IMEMECore.BondingCurveParams memory curve
    ) external pure override returns (uint256 tokenOut) {
        if (bnbIn == 0) return 0;
        if (curve.k == 0 || curve.virtualBNBReserve == 0) revert InvalidCurve();

        // New BNB reserve = current virtual BNB reserve + input BNB
        uint256 newBNBReserve = curve.virtualBNBReserve + bnbIn;

        // Calculate new token reserve based on constant product formula
        uint256 newTokenReserve = curve.k / newBNBReserve;

        // Output token amount = current virtual token reserve - new token reserve
        if (curve.virtualTokenReserve <= newTokenReserve) {return 0;}

        tokenOut = curve.virtualTokenReserve - newTokenReserve;
    }

    function calculateTokenAmountOutWithFee(
        uint256 bnbIn,
        IMEMECore.BondingCurveParams memory curve,
        uint256 feeRate
    ) external pure override returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB) {
        if (bnbIn == 0) return (0, 0, 0);
        if (curve.k == 0 || curve.virtualBNBReserve == 0) revert InvalidCurve();
        feeBNB = (bnbIn * feeRate) / 10000;
        netBNB = bnbIn - feeBNB;
        // New BNB reserve = current virtual BNB reserve + input BNB
        uint256 newBNBReserve = curve.virtualBNBReserve + netBNB;

        uint256 newTokenReserve = curve.k / newBNBReserve;
        if (curve.virtualTokenReserve <= newTokenReserve) {
            return (0, netBNB, feeBNB);
        }
        tokenOut = curve.virtualTokenReserve - newTokenReserve;
    }

    /**
     * @dev Calculate BNB output amount for given token input using bonding curve
     * @param tokenIn Token input amount
     * @param curve Bonding curve parameters
     * @return bnbOut BNB output amount
     */
    function calculateBNBAmountOut(
        uint256 tokenIn,
        IMEMECore.BondingCurveParams memory curve
    ) external pure override returns (uint256) {
        if (tokenIn == 0) return 0;
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();
        uint256 newTokenReserve = curve.virtualTokenReserve + tokenIn;
        uint256 newBNBReserve = curve.k / newTokenReserve;
        if (curve.virtualBNBReserve <= newBNBReserve) return 0;
        return curve.virtualBNBReserve - newBNBReserve;
    }

    function calculateBNBAmountOutWithFee(
        uint256 tokenIn,
        IMEMECore.BondingCurveParams memory curve,
        uint256 feeRate
    ) external pure override returns (uint256 netBNB, uint256 feeBNB) {
        if (tokenIn == 0) return (0, 0);
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();

        uint256 newTokenReserve = curve.virtualTokenReserve + tokenIn;
        uint256 newBNBReserve = curve.k / newTokenReserve;

        if (curve.virtualBNBReserve <= newBNBReserve) return (0, 0);
        uint256 grossBNB = curve.virtualBNBReserve - newBNBReserve;
        feeBNB = (grossBNB * feeRate) / 10000;
        netBNB = grossBNB - feeBNB;
    }

    function calculateRequiredBNB(
        uint256 tokenOut,
        IMEMECore.BondingCurveParams memory curve
    ) external pure override returns (uint256 bnbIn) {
        if (tokenOut == 0) return 0;
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();
        // Calculate new token reserve after purchase
        uint256 newTokenReserve = curve.virtualTokenReserve - tokenOut;
        // Calculate new BNB reserve using constant product formula: k = newBNBReserve * newTokenReserve
        uint256 newBNBReserve = curve.k / newTokenReserve;
        // Required BNB input = new BNB reserve - current BNB reserve
        if (newBNBReserve <= curve.virtualBNBReserve) {
            return 0;
        }
        bnbIn = newBNBReserve - curve.virtualBNBReserve;
    }

    /**
     * @dev Get current price from bonding curve
     * @param curve Bonding curve parameters
     * @return price Price in wei (BNB per token * 1e18)
     */
    function getPrice(
        IMEMECore.BondingCurveParams memory curve
    ) external pure override returns (uint256) {
        if (curve.virtualTokenReserve == 0) return 0;
        // Price = BNB reserve / Token reserve (in wei)
        return (curve.virtualBNBReserve * 1e18) / curve.virtualTokenReserve;
    }

    // Square root calculation (Babylonian method)
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @dev Emergency withdrawal function for admin
     * @param token Token address (address(0) for BNB)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
    }
    receive() external payable {}
} 