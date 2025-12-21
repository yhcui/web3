// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IXXXCore} from "./interfaces/IXXXCore.sol";
import {IXXXFactory} from "./interfaces/IXXXFactory.sol";
import {IXXXHelper} from "./interfaces/IXXXHelper.sol";
import {IXXXVesting} from "./interfaces/IXXXVesting.sol";
import {XXXToken} from "./XXXToken.sol";

contract XXXCore is IXXXCore, Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // System configuration
    uint256 public constant REQUEST_EXPIRY = 3600; // 1 hour
    uint256 public constant MIN_LIQUIDITY = 10 ether; // Graduation threshold: 10 tokens
    uint256 public constant MAX_INITIAL_BUY_PERCENTAGE = 9990;
    uint256 public  creationFee;
    uint256 public  preBuyFeeRate;
    uint256 public  tradingFeeRate;
    uint256 public  graduationPlatformFeeRate;
    uint256 public  graduationCreatorFeeRate;
    uint256 public  minLockTime;

    // Contract dependencies
    IXXXFactory public factory;
    IXXXHelper public helper;
    IXXXVesting public vesting;
    address public platformFeeReceiver;
    address public marginReceiver;  // Address to receive margin deposits
    uint256 public CHAIN_ID;

    // Storage mappings
    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => BondingCurveParams) public bondingCurve;
    mapping(bytes32 => bool) public usedRequestIds;
    address public graduateFeeReceiver;

    modifier validToken(address token) {
        if (tokenInfo[token].creator == address(0)) revert InvalidCreatorParameters();
        _;
    }

    modifier onlyTradingToken(address token) {
        _onlyTradingToken(token);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the XXXCore contract
     * @param _factory Address of the XXXFactory contract
     * @param _helper Address of the XXXHelper contract
     * @param _signer Address authorized to sign creation requests
     * @param _platformFeeReceiver Address to receive platform fees
     * @param _admin Admin address with full control
     */
    function initialize(
        address _factory,
        address _helper,
        address _signer,
        address _platformFeeReceiver,
        address _marginReceiver,
        address _graduateFeeReceiver,
        address _admin
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        CHAIN_ID = block.chainid;
        factory = IXXXFactory(_factory);
        helper = IXXXHelper(_helper);
        platformFeeReceiver = _platformFeeReceiver;
        marginReceiver = _marginReceiver;
        graduateFeeReceiver = _graduateFeeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(SIGNER_ROLE, _signer);
        _grantRole(DEPLOYER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        creationFee = 0.05 ether;
        preBuyFeeRate = 300;
        tradingFeeRate = 100;
        graduationPlatformFeeRate = 550;
        graduationCreatorFeeRate = 250;
        minLockTime = 86400;
    }

    /**
    * @dev Create a new token with bonding curve mechanism
     * @param data Encoded CreateTokenParams containing token creation parameters
     * @param signature Signature to verify the creation request
     */
    function createToken(
        bytes calldata data,
        bytes calldata signature
    ) external payable nonReentrant whenNotPaused returns (address tokenAddress){
        if (msg.value < creationFee) revert InsufficientFee();
        // 1. Decode parameters
        IXXXCore.CreateTokenParams memory params = abi.decode(data, (IXXXCore.CreateTokenParams));

        // 2. Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(data, CHAIN_ID, address(this)));
        address signer = messageHash.recover(signature);
        if (!hasRole(SIGNER_ROLE, signer)) revert InvalidSigner();

        // 3. Validate request
        if (block.timestamp > params.timestamp + REQUEST_EXPIRY) revert RequestExpired();
        if (usedRequestIds[params.requestId]) revert RequestAlreadyProcessed();

        // Validate token parameters
        if (params.saleAmount > params.totalSupply) revert InvalidSaleParameters();
        if (params.saleAmount == 0) revert InvalidSaleParameters();
        if (params.saleAmount < params.totalSupply * params.initialBuyPercentage / 10000) revert InvalidSaleParameters();

        // Validate initial buy percentage
        if (params.initialBuyPercentage > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidInitialBuyPercentage();

        // 4. Calculate total payment required
        uint256 totalPaymentRequired = creationFee;
        uint256 initialTokens = 0;
        uint256 initialBNB = 0;
        uint256 adjustedBNBReserve = params.virtualBNBReserve;
        uint256 adjustedTokenReserve = params.virtualTokenReserve;
        uint256 preBuyFee;

        // Add margin to total payment if specified
        if (params.marginBnb > 0) {
            totalPaymentRequired += params.marginBnb;
        }

        // Calculate initial buy if requested
        if (params.initialBuyPercentage > 0) {
            // Calculate initial buy amounts
            (initialTokens, initialBNB, adjustedBNBReserve, adjustedTokenReserve) =
            _calculateInitialBuy(
                params.totalSupply,
                params.virtualBNBReserve,
                params.virtualTokenReserve,
                params.initialBuyPercentage
            );

            // Add initial buy amount to total payment
            preBuyFee = (initialBNB * preBuyFeeRate) / 10000;
            totalPaymentRequired += initialBNB + preBuyFee;
        }

        // Validate payment
        if (msg.value < totalPaymentRequired) revert InsufficientFee();

        // 5. Mark request as processed
        usedRequestIds[params.requestId] = true;

        // 6. Deploy token
        tokenAddress = factory.deployToken(
            params.name,
            params.symbol,
            params.totalSupply,
            params.timestamp,
            params.nonce
        );

        address pair = helper.getPairAddress(tokenAddress);
        if (pair == address(0)) revert InvalidPair();
        XXXToken(tokenAddress).setPair(pair);

        // 7. Initialize Bonding Curve with adjusted values
        bondingCurve[tokenAddress] = BondingCurveParams({
            virtualBNBReserve: adjustedBNBReserve,
            virtualTokenReserve: adjustedTokenReserve,
            k: params.virtualBNBReserve * params.virtualTokenReserve, // Keep original k constant
            availableTokens: params.saleAmount - initialTokens,
            collectedBNB: initialBNB
        });

        // 8. Register token information
        // Always use TRADING status - the modifier will check launchTime
        tokenInfo[tokenAddress] = TokenInfo({
            creator: params.creator,
            createdAt: block.timestamp,
            launchTime: params.launchTime,
            status: TokenStatus.TRADING,  // Always TRADING, time check in modifier
            liquidityPool: pair
        });

        // 9. Set token transfer mode
        // Always set to controlled mode - trading will be restricted by launchTime check
        XXXToken(tokenAddress).setTransferMode(
            XXXToken.TransferMode.MODE_TRANSFER_CONTROLLED
        );

        // 9.5. Set vesting contract if configured
        if (address(vesting) != address(0)) {
            XXXToken(tokenAddress).setVestingContract(address(vesting));
        }

        // 10. Process initial buy if applicable
        if (initialTokens > 0) {
            // Process vesting allocations if provided
            if (params.vestingAllocations.length > 0 && address(vesting) != address(0)) {
                // Use internal function to handle vesting creation
                uint256 tokensToTransfer = _createVestingSchedules(
                    tokenAddress,
                    params.creator,
                    initialTokens,
                    params.initialBuyPercentage,
                    params.totalSupply,
                    params.vestingAllocations
                );

                // Transfer non-vested tokens directly to creator
                if (tokensToTransfer > 0) {
                    IERC20(tokenAddress).safeTransfer(params.creator, tokensToTransfer);
                }
            } else {
                // No vesting, transfer all tokens directly to creator
                IERC20(tokenAddress).safeTransfer(params.creator, initialTokens);
            }

            // Emit initial buy event
            emit TokenCreatedWithInitialBuy(
                tokenAddress,
                params.creator,
                initialTokens,
                initialBNB,
                params.initialBuyPercentage
            );
        }

        // 11. Process margin if applicable
        if (params.marginBnb > 0) {
            // Check margin receiver is set
            if (marginReceiver == address(0)) revert MarginReceiverNotSet();

            // Transfer margin to margin receiver
            payable(marginReceiver).transfer(params.marginBnb);

            // Emit margin deposited event with lock time
            emit MarginDeposited(
                tokenAddress,
                params.creator,
                params.marginBnb,
                params.marginTime
            );
        }

        _sendValue(platformFeeReceiver, preBuyFee);
        _sendValue(platformFeeReceiver, creationFee);

        // 12. Refund excess payment
        if (msg.value > totalPaymentRequired) {
            payable(msg.sender).transfer(msg.value - totalPaymentRequired);
        }

        // 13. Emit token creation event
        emit TokenCreated(tokenAddress, params.creator, params.name, params.symbol, params.totalSupply, params.requestId);
    }

    /**
     * @dev Buy tokens from the bonding curve
     * @param token Token address to buy
     * @param minTokenAmount Minimum token amount to receive (slippage protection)
     * @param deadline Transaction expiration timestamp
     */
    function buy(
        address token,
        uint256 minTokenAmount,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused validToken(token) onlyTradingToken(token) {
        if (block.timestamp > deadline || deadline >= block.timestamp + 1 days) revert TransactionExpired();
        if (msg.value == 0) revert InvalidNativeAmount();

        uint256 tradingFee = (msg.value * tradingFeeRate) / 10000;
        uint256 netBNBAmount = msg.value - tradingFee;
        // Calculate purchase amount
        uint256 tokenAmount = helper.calculateTokenAmountOut(netBNBAmount, bondingCurve[token]);

        // Slippage protection
        if (tokenAmount > bondingCurve[token].availableTokens) {
            tokenAmount = bondingCurve[token].availableTokens;
            netBNBAmount = helper.calculateRequiredBNB(tokenAmount, bondingCurve[token]);
            tradingFee = (netBNBAmount * tradingFeeRate) / (10000 - tradingFeeRate);
            uint256 actualPayment = netBNBAmount + tradingFee;

            if (msg.value > actualPayment) {
                payable(msg.sender).transfer(msg.value - actualPayment);
            }
        }
        if (tokenAmount < minTokenAmount) revert SlippageExceeded();

        // Update reserves
        bondingCurve[token].virtualBNBReserve += netBNBAmount;
        bondingCurve[token].virtualTokenReserve -= tokenAmount;
        bondingCurve[token].availableTokens -= tokenAmount;
        bondingCurve[token].collectedBNB += netBNBAmount;

        _sendValue(platformFeeReceiver, tradingFee);
        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, tokenAmount);

        // Check graduation conditions
        if (bondingCurve[token].availableTokens < MIN_LIQUIDITY) {
            _changeTokenStatus(token, TokenStatus.PENDING_GRADUATION);
            XXXToken(token).setTransferMode(XXXToken.TransferMode.MODE_TRANSFER_RESTRICTED);
        }

        emit TokenBought(
            token,
            msg.sender,
            netBNBAmount,
            tokenAmount,
            tradingFee,
            bondingCurve[token].virtualBNBReserve,
            bondingCurve[token].virtualTokenReserve,
            bondingCurve[token].availableTokens,
            bondingCurve[token].collectedBNB
        );
    }

    /**
     * @dev Sell tokens to the bonding curve
     * @param token Token address to sell
     * @param tokenAmount Amount of tokens to sell
     * @param minBNBAmount Minimum BNB amount to receive (slippage protection)
     * @param deadline Transaction expiration timestamp
     */
    function sell(
        address token,
        uint256 tokenAmount,
        uint256 minBNBAmount,
        uint256 deadline
    ) external nonReentrant whenNotPaused validToken(token) onlyTradingToken(token) {
        if (block.timestamp > deadline) revert TransactionExpired();
        if (tokenAmount == 0) revert InvalidParameters();

        // Check user balance
        if (IERC20(token).balanceOf(msg.sender) < tokenAmount) revert InsufficientBalance();

        // Calculate BNB amount from sale
        uint256 bnbAmount = helper.calculateBNBAmountOut(tokenAmount, bondingCurve[token]);
        uint256 tradingFee = (bnbAmount * tradingFeeRate) / 10000;
        uint256 netBNBAmount = bnbAmount - tradingFee;

        if (netBNBAmount < minBNBAmount) revert SlippageExceeded();
        if (bnbAmount > bondingCurve[token].collectedBNB) revert InsufficientBalance();

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        bondingCurve[token].virtualBNBReserve -= bnbAmount;
        bondingCurve[token].virtualTokenReserve += tokenAmount;
        bondingCurve[token].availableTokens += tokenAmount;
        bondingCurve[token].collectedBNB -= bnbAmount;

        _sendValue(platformFeeReceiver, tradingFee);
        _sendValue(msg.sender, netBNBAmount);

        emit TokenSold(
            token,
            msg.sender,
            tokenAmount,
            netBNBAmount,
            tradingFee,
            bondingCurve[token].virtualBNBReserve,
            bondingCurve[token].virtualTokenReserve,
            bondingCurve[token].availableTokens,
            bondingCurve[token].collectedBNB
        );
    }

    /**
     * @dev Graduate token from bonding curve to AMM liquidity pool
     * @param token Token address to graduate
     */
    function graduateToken(address token) external onlyRole(DEPLOYER_ROLE) validToken(token) nonReentrant {
        TokenInfo storage info = tokenInfo[token];

        BondingCurveParams storage curve = bondingCurve[token];

        uint256 collectedBNB = curve.collectedBNB;
        uint256 remainingTokens = curve.availableTokens;

        uint256 platformFee = collectedBNB * graduationPlatformFeeRate / 10000;
        uint256 creatorFee = collectedBNB * graduationCreatorFeeRate / 10000;
        uint256 liquidityBNB = collectedBNB - platformFee - creatorFee;

        uint256 tokenPlatformFee = remainingTokens * graduationPlatformFeeRate / 10000;
        uint256 tokenCreatorFee = remainingTokens * graduationCreatorFeeRate / 10000;
        uint256 liquidityTokens = remainingTokens - tokenPlatformFee - tokenCreatorFee;

        XXXToken(token).setTransferMode(XXXToken.TransferMode.MODE_NORMAL);

        require(IERC20(token).balanceOf(address(this)) >= remainingTokens, "Insufficient token for liquidity");
        IERC20(token).approve(address(helper), liquidityTokens);
        uint256 liquidityResult = helper.addLiquidityV2{value: liquidityBNB}(token, liquidityBNB, liquidityTokens);

        _changeTokenStatus(token, TokenStatus.GRADUATED);

        _sendValue(graduateFeeReceiver, platformFee);
        if (tokenPlatformFee > 0) IERC20(token).safeTransfer(graduateFeeReceiver, tokenPlatformFee);
        _sendValue(info.creator, creatorFee);
        if (tokenCreatorFee > 0) IERC20(token).safeTransfer(info.creator, tokenCreatorFee);

        emit TokenGraduated(token, liquidityBNB, liquidityTokens, liquidityResult);
    }

    /**
     * @dev Pause trading for a specific token
     * @param token Token address to pause
     */
    function pauseToken(address token) external onlyRole(PAUSER_ROLE) validToken(token) {
        _changeTokenStatus(token, TokenStatus.PAUSED);
        emit TokenPaused(token);
    }

    function unpauseToken(address token) external onlyRole(PAUSER_ROLE) validToken(token) {
        if (tokenInfo[token].status != TokenStatus.PAUSED) revert InvalidPausedStatus();
        _changeTokenStatus(token, TokenStatus.TRADING);
        emit TokenUnpaused(token);
    }

    /**
     * @dev Blacklist a token (emergency measure)
     * @param token Token address to blacklist
     */
    function blacklistToken(address token) external onlyRole(ADMIN_ROLE) validToken(token) {
        _changeTokenStatus(token, TokenStatus.BLACKLISTED);
        emit TokenBlacklisted(token);
    }

    function removeFromBlacklist(address token) external onlyRole(ADMIN_ROLE) validToken(token) {
        if (tokenInfo[token].status != TokenStatus.BLACKLISTED) revert InvalidBlackListedStatus();
        _changeTokenStatus(token, TokenStatus.TRADING);
        emit TokenRemovedFromBlacklist(token);
    }

    /**
     * @dev Get token information
     * @param token Token address
     * @return TokenInfo structure containing token details
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory) {
        return tokenInfo[token];
    }

    /**
     * @dev Get bonding curve parameters for a token
     * @param token Token address
     * @return BondingCurveParams structure containing curve parameters
     */
    function getBondingCurve(address token) external view returns (BondingCurveParams memory) {
        return bondingCurve[token];
    }

    /**
     * @dev Calculate token amount for a given BNB input
     * @param token Token address
     * @param bnbAmount BNB amount to spend
     * @return tokenAmount Estimated token amount to receive
     */
    function calculateBuyAmount(address token, uint256 bnbAmount) external view returns (uint256 tokenAmount)    {
        BondingCurveParams memory curve = bondingCurve[token];
        tokenAmount = helper.calculateTokenAmountOut(bnbAmount, curve);
        if (tokenAmount > curve.availableTokens) {
            tokenAmount = curve.availableTokens;
        }
    }

    function calculateBuyAmountWithFee(address token, uint256 bnbAmount) external view returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB)    {
        BondingCurveParams memory curve = bondingCurve[token];
        (tokenOut, netBNB, feeBNB) = helper.calculateTokenAmountOutWithFee(bnbAmount, curve, tradingFeeRate);
        if (tokenOut > curve.availableTokens) {
            tokenOut = curve.availableTokens;
            netBNB = helper.calculateRequiredBNB(tokenOut, curve);
            feeBNB = (netBNB * tradingFeeRate) / (10000 - tradingFeeRate);
        }
    }

    /**
     * @dev Calculate BNB return for a given token amount
     * @param token Token address
     * @param tokenAmount Token amount to sell
     * @return bnbAmount Estimated BNB amount to receive
     */
    function calculateSellReturn(address token, uint256 tokenAmount) external view returns (uint256)    {
        return helper.calculateBNBAmountOut(tokenAmount, bondingCurve[token]);
    }

    function calculateSellReturnWithFee(address token, uint256 tokenAmount) external view returns (uint256 netBNB, uint256 feeBNB)    {
        (netBNB, feeBNB) = helper.calculateBNBAmountOutWithFee(tokenAmount, bondingCurve[token], tradingFeeRate);
    }

    /**
     * @dev Calculate the BNB required for initial buy
     * @param totalSupply Total tokens available for sale
     * @param virtualBNBReserve Initial virtual BNB reserve
     * @param virtualTokenReserve Initial virtual token reserve
     * @param percentageBP Percentage to buy in basis points (0-9990)
     * @return totalPayment Amount of BNB needed for the initial buy
     */
    function calculateInitialBuyBNB(
        uint256 totalSupply,
        uint256 virtualBNBReserve,
        uint256 virtualTokenReserve,
        uint256 percentageBP
    ) external view returns (uint256 totalPayment, uint256 preBuyFee) {
        if (percentageBP == 0) return (0, 0);
        if (percentageBP > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidParameters();

        (, uint256 bnbRequired,,) = _calculateInitialBuy(
            totalSupply,
            virtualBNBReserve,
            virtualTokenReserve,
            percentageBP
        );
        preBuyFee = (bnbRequired * preBuyFeeRate) / 10000;
        totalPayment = bnbRequired + preBuyFee;
    }

    function _sendValue(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (to == address(0)) {
            to = platformFeeReceiver;
            require(to != address(0), "Platform fee receiver not set");
        }
        uint32 size;
        assembly {
            size := extcodesize(to)
        }
        if (size > 0) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) {
                (bool fallbackSuccess,) = payable(platformFeeReceiver).call{value: amount}("");
                require(fallbackSuccess, "BNB_SEND_FAILED_TO_FALLBACK");
                emit CreatorFeeRedirected(to, platformFeeReceiver, amount);
            }
        } else {
            (bool ok,) = payable(to).call{value: amount}("");
            require(ok, "BNB_SEND_FAILED");
        }
    }

    // Internal function to handle vesting creation
    function _createVestingSchedules(
        address tokenAddress,
        address beneficiary,
        uint256 initialTokens,
        uint256 initialBuyPercentage,
        uint256 totalSupply,
        VestingAllocation[] memory vestingAllocations
    ) internal returns (uint256 tokensToTransfer) {
        uint256 totalVestedAmount;
        uint256 totalBurnedAmount;

        for (uint256 i = 0; i < vestingAllocations.length; i++) {
            if (vestingAllocations[i].amount == 0) {
                revert InvalidAmountParameters();
            }
            if (vestingAllocations[i].mode == VestingMode.BURN) {
                totalBurnedAmount += vestingAllocations[i].amount;
            } else {
                totalVestedAmount += vestingAllocations[i].amount;
                if (vestingAllocations[i].mode == VestingMode.LINEAR) {
                    if (vestingAllocations[i].duration == 0) {
                        revert InvalidDurationParameters();
                    }
                    if (vestingAllocations[i].duration < minLockTime) {
                        revert InvalidDurationParameters();
                    }
                }
            }
        }

        if (initialBuyPercentage < totalVestedAmount + totalBurnedAmount) revert InvalidVestingParameters();
        // Calculate actual token amounts for vesting
        uint256 tokensToVest = (totalSupply * totalVestedAmount) / 10000;
        uint256 tokensToBurn = (totalSupply * totalBurnedAmount) / 10000;
        if (initialTokens < tokensToVest + tokensToBurn) revert InvalidParameters();

        tokensToTransfer = initialTokens - tokensToVest - tokensToBurn;
        if (tokensToBurn > 0) {
            XXXToken(tokenAddress).burn(tokensToBurn);
            emit XXXTokensBurned(tokenAddress, tokensToBurn);
        }
        // Create vesting schedules if there are tokens to vest
        if (tokensToVest > 0) {
            // Prepare vesting allocations with actual token amounts
            VestingAllocation[] memory actualVestingAllocations = new VestingAllocation[](vestingAllocations.length);

            uint256 allocatedTokens;
            TokenInfo memory info = tokenInfo[tokenAddress];
            uint256 actualLaunchTime = info.launchTime;
            if (actualLaunchTime == 0) {
                actualLaunchTime = block.timestamp;
            }
            int256 lastNonBurnIndex = - 1;
            for (uint256 i = 0; i < vestingAllocations.length; i++) {
                if (vestingAllocations[i].mode != VestingMode.BURN) {
                    lastNonBurnIndex = int256(i);
                }
            }
            for (uint256 i = 0; i < vestingAllocations.length; i++) {
                uint256 allocationAmount;
                if (vestingAllocations[i].mode == VestingMode.BURN) {
                    allocationAmount = 0;
                } else if (int256(i) == lastNonBurnIndex) {
                    allocationAmount = tokensToVest - allocatedTokens;
                } else {
                    allocationAmount = (totalSupply * vestingAllocations[i].amount) / 10000;
                    allocatedTokens += allocationAmount;
                }
                actualVestingAllocations[i] = VestingAllocation({
                    amount: allocationAmount,
                    launchTime: actualLaunchTime,
                    duration: vestingAllocations[i].duration,
                    mode: vestingAllocations[i].mode
                });
            }

            // Approve vesting contract to transfer tokens
            IERC20(tokenAddress).approve(address(vesting), tokensToVest);

            // Create vesting schedules
            vesting.createVestingSchedules(
                tokenAddress,
                beneficiary,
                actualVestingAllocations
            );

            // Emit vesting created event
            emit VestingCreated(
                tokenAddress,
                beneficiary,
                tokensToVest,
                actualVestingAllocations.length
            );
        }

        return tokensToTransfer;
    }

    /**
   * @dev Calculate initial buy amounts based on percentage
     * @param totalSupply Total tokens available for sale
     * @param virtualBNBReserve Initial virtual BNB reserve
     * @param virtualTokenReserve Initial virtual token reserve
     * @param percentageBP Percentage in basis points (0-9990)
     * @return tokensOut Amount of tokens to purchase
     * @return bnbRequired Amount of BNB required for purchase
     * @return newBNBReserve New virtual BNB reserve after purchase
     * @return newTokenReserve New virtual token reserve after purchase
     */
    function _calculateInitialBuy(
        uint256 totalSupply,
        uint256 virtualBNBReserve,
        uint256 virtualTokenReserve,
        uint256 percentageBP
    ) internal pure returns (
        uint256 tokensOut,
        uint256 bnbRequired,
        uint256 newBNBReserve,
        uint256 newTokenReserve
    ) {
        if (percentageBP > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidPercentageBP();
        // Calculate target token amount based on percentage
        tokensOut = (totalSupply * percentageBP) / 10000;

        // Calculate new reserves using constant product formula
        // k = virtualBNBReserve * virtualTokenReserve
        // After buy: (virtualBNBReserve + bnbIn) * (virtualTokenReserve - tokensOut) = k
        uint256 k = virtualBNBReserve * virtualTokenReserve;
        newTokenReserve = virtualTokenReserve - tokensOut;
        newBNBReserve = k / newTokenReserve;
        bnbRequired = newBNBReserve - virtualBNBReserve;

        return (tokensOut, bnbRequired, newBNBReserve, newTokenReserve);
    }

    function _changeTokenStatus(address token, TokenStatus newStatus) internal {
        TokenStatus oldStatus = tokenInfo[token].status;
        tokenInfo[token].status = newStatus;
        emit TokenStatusChanged(token, oldStatus, newStatus);
    }

    function _onlyTradingToken(address token) internal view {
        TokenInfo memory info = tokenInfo[token];
        if (info.status != TokenStatus.TRADING) {
            revert TokenNotTrading();
        }
        if (block.timestamp < info.launchTime) {
            revert TokenNotLaunchedYet();
        }
    }

    /**
     * @dev Set platform fee receiver address
     * @param _receiver New platform fee receiver address
     */
    function setPlatformFeeReceiver(address _receiver) external onlyRole(ADMIN_ROLE) {
        if (_receiver == address(0)) revert ZeroAddress();
        address oldPlatformFeeReceiver = platformFeeReceiver;
        platformFeeReceiver = _receiver;
        emit PlatformFeeReceiverChanged(oldPlatformFeeReceiver, _receiver);

    }

    /**
     * @dev Set graduate fee receiver address
     * @param _receiver New graduate fee receiver address
     */
    function setGraduateFeeReceiver(address _receiver) external onlyRole(ADMIN_ROLE) {
        if (_receiver == address(0)) revert ZeroAddress();
        address oldGraduateFeeReceiver = graduateFeeReceiver;
        graduateFeeReceiver = _receiver;
        emit GraduateFeeReceiverChanged(oldGraduateFeeReceiver, _receiver);
    }

    /**
     * @dev Set factory contract address
     * @param _factory New factory contract address
     */
    function setFactory(address _factory) external onlyRole(ADMIN_ROLE) {
        if (_factory == address(0)) revert ZeroAddress();
        address oldFactory = address(factory);
        factory = IXXXFactory(_factory);
        emit FactoryChanged(oldFactory, _factory);
    }

    /**
     * @dev Set helper contract address
     * @param _helper New helper contract address
     */
    function setHelper(address _helper) external onlyRole(ADMIN_ROLE) {
        if (_helper == address(0)) revert ZeroAddress();
        address oldHelper = address(helper);
        helper = IXXXHelper(_helper);
        emit HelperChanged(oldHelper, _helper);
    }

    /**
     * @dev Set vesting contract address
     * @param _vesting New vesting contract address
     */
    function setVesting(address _vesting) external onlyRole(ADMIN_ROLE) {
        if (_vesting == address(0)) revert ZeroAddress();
        address oldVesting = _vesting;
        vesting = IXXXVesting(_vesting);
        emit VestingChanged(oldVesting, _vesting);
    }

    /**
     * @dev Set margin receiver address
     * @param _marginReceiver New margin receiver address
     */
    function setMarginReceiver(address _marginReceiver) external onlyRole(ADMIN_ROLE) {
        if (_marginReceiver == address(0)) revert ZeroAddress();
        address oldMarginReceiver = marginReceiver;
        marginReceiver = _marginReceiver;
        emit MarginReceiverChanged(oldMarginReceiver, _marginReceiver);
    }

    function setCreationFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        if (_fee > 0.1 ether) revert InvalidAmountParameters();
        creationFee = _fee;
        emit CreationFeeChanged(_fee);
    }

    function setPreBuyFeeRate(uint256 _rate) external onlyRole(ADMIN_ROLE) {
        if (_rate > 600) revert InvalidAmountParameters();
        preBuyFeeRate = _rate;
        emit PreBuyFeeRateChanged(_rate);
    }

    function setTradingFeeRate(uint256 _rate) external onlyRole(ADMIN_ROLE) {
        if (_rate > 200) revert InvalidAmountParameters();
        tradingFeeRate = _rate;
        emit TradingFeeRateChanged(_rate);
    }

    function setGraduationFeeRates(uint256 _platformRate, uint256 _creatorRate) external onlyRole(ADMIN_ROLE) {
        if (_platformRate > 1100 || _creatorRate > 500) revert InvalidAmountParameters();
        graduationPlatformFeeRate = _platformRate;
        graduationCreatorFeeRate = _creatorRate;
        emit GraduationFeeRatesChanged(_platformRate, _creatorRate);
    }

    function setMinLockTime(uint256 _time) external onlyRole(ADMIN_ROLE) {
        minLockTime = _time;
        emit MinLockTimeChanged(_time);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    /**
      * @dev Emergency withdraw tokens or BNB from contract
      * @param token Token address (address(0) for BNB)
      * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    receive() external payable {}
} 