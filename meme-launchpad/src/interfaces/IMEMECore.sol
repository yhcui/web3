// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVestingParams} from "./IVestingParams.sol";
import {IBondingCurveParams} from "./IBondingCurveParams.sol";

interface IMEMECore is IVestingParams, IBondingCurveParams {
    enum TokenStatus {
        NOT_CREATED,        // Not created
        TRADING,           // Trading
        PENDING_GRADUATION, // Pending graduation
        GRADUATED,         // Graduated
        PAUSED,           // Paused
        BLACKLISTED       // Blacklisted
    }

    error InvalidSigner();
    error RequestExpired();
    error RequestAlreadyProcessed();
    error InsufficientFee();
    error InvalidPair();
    error TokenNotTrading();
    error TokenNotLaunchedYet();
    error SlippageExceeded();
    error InvalidStatus();
    error Unauthorized();
    error InvalidCreatorParameters();
    error InvalidAmountParameters();
    error InvalidDurationParameters();
    error InvalidVestingParameters();
    error InvalidParameters();
    error InvalidSaleParameters();
    error InvalidInitialBuyPercentage();
    error TransactionExpired();
    error InvalidNativeAmount();
    error InsufficientBalance();
    error InsufficientMargin();
    error MarginReceiverNotSet();
    error InvalidPercentageBP();
    error InvalidPausedStatus();
    error InvalidBlackListedStatus();
    error ZeroAddress();


    struct TokenInfo {
        address creator;
        uint256 createdAt;
        uint256 launchTime;
        TokenStatus status;
        address liquidityPool;  // LP address
    }


    struct CreateTokenParams {
        string name;                    // Token name
        string symbol;                  // Token symbol
        uint256 totalSupply;           // Total supply
        uint256 saleAmount;            // Token amount for sale
        uint256 virtualBNBReserve;     // Initial virtual BNB reserve
        uint256 virtualTokenReserve;   // Initial virtual Token reserve
        uint256 launchTime;            // Launch time (0 means immediate)
        address creator;               // Creator address
        uint256 timestamp;             // Request timestamp
        bytes32 requestId;             // Unique request ID
        uint256 nonce;                 // Nonce
        uint256 initialBuyPercentage;  // Initial buy percentage in basis points (0-9990 = 0%-99.9%)
        uint256 marginBnb;              // Margin amount in BNB
        uint256 marginTime;             // Margin lock time (seconds)
        VestingAllocation[] vestingAllocations; // Vesting allocations for initial buy
    }

    // Event definitions
    event TokenCreated(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        uint256 totalSupply,
        bytes32 requestId
    );

    event TokenBought(
        address indexed token,
        address indexed buyer,
        uint256 bnbAmount,
        uint256 tokenAmount,
        uint256 tradingFee,
        uint256 virtualBNBReserve,
        uint256 virtualTokenReserve,
        uint256 availableTokens,
        uint256 collectedBNB
    );

    event TokenSold(
        address indexed token,
        address indexed seller,
        uint256 tokenAmount,
        uint256 bnbAmount,
        uint256 tradingFee,
        uint256 virtualBNBReserve,
        uint256 virtualTokenReserve,
        uint256 availableTokens,
        uint256 collectedBNB
    );

    event TokenGraduated(
        address indexed token,
        uint256 liquidityBNB,
        uint256 liquidityTokens,
        uint256 liquidityResult
    );

    event TokenStatusChanged(
        address indexed token,
        TokenStatus oldStatus,
        TokenStatus newStatus
    );

    event TokenPaused(address indexed token);
    event TokenUnpaused(address indexed token);
    event TokenBlacklisted(address indexed token);
    event TokenRemovedFromBlacklist(address indexed token);
    event CreatorFeeRedirected(address indexed to, address indexed platformFeeReceiver, uint256 amount);
    event PlatformFeeReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    event GraduateFeeReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    event FactoryChanged(address indexed oldFactory, address indexed newFactory);
    event HelperChanged(address indexed oldHelper, address indexed newHelper);
    event VestingChanged(address indexed oldVesting, address indexed newVesting);
    event MarginReceiverChanged(address indexed oldMarginReceiver, address indexed newMarginReceiver);
    event CreationFeeChanged(uint256 creationFee);
    event PreBuyFeeRateChanged(uint256 preBuyFeeRate);
    event TradingFeeRateChanged(uint256 tradingFeeRate);
    event GraduationFeeRatesChanged(uint256 platformRate, uint256 creatorRate);
    event MinLockTimeChanged(uint256 minLockTime);

    // Event for token creation with initial buy
    event TokenCreatedWithInitialBuy(
        address indexed token,
        address indexed creator,
        uint256 initialTokensPurchased,
        uint256 initialBNBSpent,
        uint256 actualPercentage
    );

    // Event for margin deposit
    event MarginDeposited(
        address indexed token,
        address indexed creator,
        uint256 marginAmount,
        uint256 lockTime
    );

    // Event for vesting creation
    event VestingCreated(
        address indexed token,
        address indexed beneficiary,
        uint256 totalVestedAmount,
        uint256 scheduleCount
    );

    event XXXTokensBurned(address indexed token, uint256 amount);

    // Core functions
    function createToken(bytes calldata data, bytes calldata signature) external payable returns (address);

    function buy(address token, uint256 minTokenAmount, uint256 deadline) external payable;

    function sell(address token, uint256 tokenAmount, uint256 minBNBAmount, uint256 deadline) external;

    function graduateToken(address token) external;

    function pauseToken(address token) external;

    function blacklistToken(address token) external;

    // Query functions
    function getTokenInfo(address token) external view returns (TokenInfo memory);

    function getBondingCurve(address token) external view returns (BondingCurveParams memory);

    function calculateBuyAmount(address token, uint256 bnbAmount) external view returns (uint256);

    function calculateBuyAmountWithFee(address token, uint256 bnbAmount) external view returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB);

    function calculateSellReturn(address token, uint256 tokenAmount) external view returns (uint256);

    function calculateSellReturnWithFee(address token, uint256 tokenAmount) external view returns (uint256 netBNB, uint256 feeBNB);
} 