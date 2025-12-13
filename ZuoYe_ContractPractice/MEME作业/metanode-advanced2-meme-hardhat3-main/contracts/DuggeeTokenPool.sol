// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title DuggeeTokenPool - 流动性池合约
 * @dev 这是一个去中心化交易所流动性池，实现DuggeeToken与其他ERC20代币的交换功能
 *
 * 主要功能：
 * 1. 流动性管理：用户可以添加和移除流动性
 * 2. 代币交换：支持DuggeeToken与其他代币的双向交换
 * 3. 交易费用：收取交易手续费，支持手续费提取
 * 4. 价格发现：通过恒定乘积公式实现代币价格发现
 *
 * 算法：恒定乘积公式 (x * y = k)
 * x: DuggeeToken储备量, y: 配对代币储备量, k: 常数
 *
 */
contract DuggeeTokenPool is Ownable {

    // ========== 代币合约地址 ==========

    /**
     * @dev DuggeeToken合约实例
     */
    IERC20 public duggeeToken;

    /**
     * @dev 配对代币合约实例（例如：USDT、ETH等）
     */
    IERC20 public token;

    // ========== 流动性相关变量 ==========

    /**
     * @dev 流动性池的总流动性
     * 使用恒定乘积公式计算：sqrt(duggeeReserve * tokenReserve)
     */
    uint256 public totalLiquidity;

    /**
     * @dev 流动性池中DuggeeToken的储备量
     */
    uint256 public duggeeReserve;

    /**
     * @dev 流动性池中配对代币的储备量
     */
    uint256 public tokenReserve;

    // ========== LP代币相关变量 ==========

    /**
     * @dev LP代币总供应量
     * LP代币代表流动性提供者在池中的份额
     */
    uint256 public totalLpTokens;

    /**
     * @dev 记录每个地址持有的LP代币数量
     * key: 流动性提供者地址, value: LP代币数量
     */
    mapping(address => uint256) public lpTokens;

    // ========== 交易费用相关变量 ==========

    /**
     * @dev 交易费百分比（千分比）
     * 默认设置为1‰（千分之一），即0.1%
     */
    uint256 public FEE_PERCENTAGE = 1;

    /**
     * @dev 费用分母常量，用于计算费用
     * 固定为1000，表示千分比的基准
     */
    uint256 public constant FEE_DENOMINATOR = 1000;

    /**
     * @dev DuggeeToken手续费余额
     * 累计收取的DuggeeToken交易手续费
     */
    uint256 public duggeeTokenFeeBalance;

    /**
     * @dev 配对代币手续费余额
     * 累计收取的配对代币交易手续费
     */
    uint256 public tokenFeeBalance;

    // ========== 构造函数 ==========

    /**
     * @dev 构造函数，初始化流动性池
     *
     * @param owner 合约所有者地址
     * @param duggeeTokenAddress DuggeeToken合约地址
     * @param tokenAddress 配对代币合约地址
     */
    constructor(address owner, address duggeeTokenAddress, address tokenAddress) Ownable(owner) {
        duggeeToken = IERC20(duggeeTokenAddress);
        token = IERC20(tokenAddress);
    }

    // ========== 事件 ==========

    /**
     * @dev 流动性添加事件
     *
     * @param provider 流动性提供者地址
     * @param duggeeAmount 添加的DuggeeToken数量
     * @param tokenAmount 添加的配对代币数量
     * @param lpTokensMinted 铸造的LP代币数量
     */
    event LiquidityAdded(address indexed provider, uint256 duggeeAmount, uint256 tokenAmount, uint256 lpTokensMinted);

    /**
     * @dev 流动性移除事件
     *
     * @param provider 流动性提供者地址
     * @param duggeeAmount 移除的DuggeeToken数量
     * @param tokenAmount 移除的配对代币数量
     * @param lpTokensBurned 销毁的LP代币数量
     */
    event LiquidityRemoved(address indexed provider, uint256 duggeeAmount, uint256 tokenAmount, uint256 lpTokensBurned);

    /**
     * @dev 代币交换事件
     *
     * @param swapper 交换者地址
     * @param fromToken 卖出的代币地址
     * @param fromAmount 卖出的代币数量（包含费用）
     * @param feeAmount 交易费用
     * @param toToken 买入的代币地址
     * @param toAmount 买入的代币数量
     */
    event Swap(address indexed swapper, address fromToken, uint256 fromAmount, uint256 feeAmount, address toToken, uint256 toAmount);

    // ========== 流动性管理功能 ==========

    /**
     * @dev 添加流动性
     *
     * 流程：
     * 1. 如果是首次添加流动性：按提供的代币数量确定初始价格
     * 2. 如果是后续添加流动性：按当前池子比例计算需要的配对代币数量
     * 3. 根据添加的流动性铸造LP代币给提供者
     * 4. 退还多余的配对代币（如果用户提供了更多）
     *
     * @param duggeeAmount 添加的DuggeeToken数量
     * @param tokenAmount 添加的配对代币数量（可能部分退还）
     * @param minTokenAmount 最少需要的配对代币数量，防滑点保护
     */
    function addLiquidity(uint256 duggeeAmount, uint256 tokenAmount, uint256 minTokenAmount) external {
        if (totalLiquidity == 0) {
            // ========== 初始流动性提供者 ==========
            // 首次添加流动性，可以任意设置初始价格
            duggeeReserve += duggeeAmount;
            tokenReserve += tokenAmount;

            // 使用恒定乘积公式计算初始流动性：sqrt(x * y)
            totalLiquidity = Math.sqrt(duggeeReserve * tokenReserve);
            totalLpTokens = totalLiquidity;  // 首次提供者获得全部LP代币
            lpTokens[msg.sender] = totalLiquidity;

            // 将代币转账到合约
            require(duggeeToken.transferFrom(msg.sender, address(this), duggeeAmount), "DuggeeToken transfer failed");
            require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

            emit LiquidityAdded(msg.sender, duggeeAmount, tokenAmount, totalLiquidity);
        } else {
            // ========== 后续流动性提供者 ==========
            // 必须按当前池子比例添加代币，以维持价格稳定

            // 根据当前比例计算需要的配对代币数量
            // requireTokenAmount = duggeeAmount * (tokenReserve / duggeeReserve)
            uint256 requireTokenAmount = (duggeeAmount * tokenReserve) / duggeeReserve;

            // 检查配对代币数量是否足够（防滑点保护）
            require(requireTokenAmount >= minTokenAmount, "Insufficient token amount provided");

            // 确保用户提供了足够数量的配对代币
            if (tokenAmount < requireTokenAmount) {
                revert("Insufficient token amount provided");
            }

            // 将代币转账到合约
            require(duggeeToken.transferFrom(msg.sender, address(this), duggeeAmount), "DuggeeToken transfer failed");
            require(token.transferFrom(msg.sender, address(this), requireTokenAmount), "Token transfer failed");

            // 如果用户提供了更多配对代币，退还多余部分
            uint256 leftTokenAmount = tokenAmount - requireTokenAmount;
            if (leftTokenAmount > 0) {
                require(token.transferFrom(msg.sender, msg.sender, leftTokenAmount), "Token refund failed");
            }

            // 更新储备量
            duggeeReserve += duggeeAmount;
            tokenReserve += requireTokenAmount;

            // 计算新的总流动性和需要铸造的LP代币
            uint256 nowTotalLiquidity = Math.sqrt(duggeeReserve * tokenReserve);
            uint256 liquidityMinted = nowTotalLiquidity - totalLiquidity;  // 新增的流动性

            // 更新流动性相关状态
            totalLiquidity = nowTotalLiquidity;
            totalLpTokens += liquidityMinted;
            lpTokens[msg.sender] += liquidityMinted;

            emit LiquidityAdded(msg.sender, duggeeAmount, requireTokenAmount, liquidityMinted);
        }
    }

    /**
     * @dev 移除流动性
     *
     * 流程：
     * 1. 检查用户是否有足够的LP代币
     * 2. 按LP代币比例计算可提取的代币数量
     * 3. 销毁LP代币并更新储备量
     * 4. 将代币转账给用户
     *
     * @param lpTokenAmount 要移除的LP代币数量
     */
    function removeLiquidity(uint256 lpTokenAmount) external {
        // 检查LP代币余额
        require(lpTokens[msg.sender] >= lpTokenAmount, "Insufficient LP tokens");

        // 按LP代币比例计算可提取的代币数量
        // 比例 = 用户LP代币 / 总LP代币
        uint256 duggeeAmount = (lpTokenAmount * duggeeReserve) / totalLpTokens;
        uint256 tokenAmount = (lpTokenAmount * tokenReserve) / totalLpTokens;

        // 销毁LP代币
        lpTokens[msg.sender] -= lpTokenAmount;
        totalLpTokens -= lpTokenAmount;

        // 更新储备量和总流动性
        duggeeReserve -= duggeeAmount;
        tokenReserve -= tokenAmount;
        totalLiquidity = Math.sqrt(duggeeReserve * tokenReserve);

        // 将代币转账给用户
        require(duggeeToken.transfer(msg.sender, duggeeAmount), "DuggeeToken transfer failed");
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");

        emit LiquidityRemoved(msg.sender, duggeeAmount, tokenAmount, lpTokenAmount);
    }

    // ========== 代币交换功能 ==========

    /**
     * @dev 代币交换功能
     *
     * 使用恒定乘积公式计算交换结果：
     * - 输入代币数量增加，输出代币数量减少
     * - 保持 x * y = k 不变
     * - 扣除交易手续费后进行交换
     *
     * @param fromToken 要卖出的代币地址
     * @param fromAmount 卖出的代币数量（包含费用）
     * @param minToAmount 最少要获得的代币数量（防滑点保护）
     */
    function swap(address fromToken, uint256 fromAmount, uint minToAmount) external {
        // 检查代币地址是否为池中支持的代币
        require(fromToken == address(duggeeToken) || fromToken == address(token), "Invalid token address");

        // 计算交易费用：费用 = 输入数量 × 费率
        uint256 feeAmount = (fromAmount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
        uint256 netFromAmount = fromAmount - feeAmount;  // 实际用于交换的代币数量

        if (fromToken == address(duggeeToken)) {
            // ========== 用DuggeeToken交换配对代币 ==========

            // 先收取手续费
            require(duggeeToken.transferFrom(msg.sender, address(this), feeAmount), "DuggeeToken transfer failed");
            duggeeTokenFeeBalance += feeAmount;

            // 再收取用于交换的代币
            require(duggeeToken.transferFrom(msg.sender, address(this), netFromAmount), "DuggeeToken transfer failed");

            // 使用恒定乘积公式计算能得到的代币数量
            // (duggeeReserve + netFromAmount) * (tokenReserve - toAmount) = duggeeReserve * tokenReserve
            // 解得：toAmount = (netFromAmount * tokenReserve) / (duggeeReserve + netFromAmount)
            uint256 toAmount = (netFromAmount * tokenReserve) / (duggeeReserve + netFromAmount);

            // 防滑点保护：确保输出数量不低于预期
            require(toAmount >= minToAmount, "Insufficient output amount");

            // 更新储备量
            duggeeReserve += netFromAmount;
            tokenReserve -= toAmount;

            // 将交换后的代币转给用户
            require(token.transfer(msg.sender, toAmount), "Token transfer failed");

            emit Swap(msg.sender, fromToken, fromAmount, feeAmount, address(token), toAmount);
        } else {
            // ========== 用配对代币交换DuggeeToken ==========

            // 先收取手续费
            require(token.transferFrom(msg.sender, address(this), feeAmount), "Token transfer failed");
            tokenFeeBalance += feeAmount;

            // 再收取用于交换的代币
            require(token.transferFrom(msg.sender, address(this), netFromAmount), "Token transfer failed");

            // 计算能得到的DuggeeToken数量
            // (tokenReserve + netFromAmount) * (duggeeReserve - toAmount) = tokenReserve * duggeeReserve
            // 解得：toAmount = (netFromAmount * duggeeReserve) / (tokenReserve + netFromAmount)
            uint256 toAmount = (netFromAmount * duggeeReserve) / (tokenReserve + netFromAmount);

            // 防滑点保护
            require(toAmount >= minToAmount, "Insufficient output amount");

            // 更新储备量
            tokenReserve += netFromAmount;
            duggeeReserve -= toAmount;

            // 将交换后的代币转给用户
            require(duggeeToken.transfer(msg.sender, toAmount), "DuggeeToken transfer failed");

            emit Swap(msg.sender, fromToken, fromAmount, feeAmount, address(duggeeToken), toAmount);
        }
    }

    // ========== 价格查询功能 ==========

    /**
     * @dev 获取当前价格（1个DuggeeToken能兑换多少配对代币）
     *
     * 价格 = tokenReserve / duggeeReserve
     * 返回值放大1e18倍以保持精度
     *
     * @return uint256 当前价格（放大1e18倍）
     */
    function getPrice() external view returns (uint256) {
        require(duggeeReserve > 0 && tokenReserve > 0, "Insufficient reserves");
        return (tokenReserve * 1e18) / duggeeReserve;
    }

    // ========== 管理员功能 ==========

    /**
     * @dev 设置交易费百分比（仅所有者）
     *
     * 注意：费用以千分比计算，如 1 表示 1‰ (0.1%)
     *
     * @param newFeePercentage 新的交易费千分比，最大不超过100‰ (10%)
     */
    function setFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 100, "Fee percentage too high");
        FEE_PERCENTAGE = newFeePercentage;
    }

    /**
     * @dev 提取交易费用（仅所有者）
     *
     * 将累计的所有交易费用提取给合约所有者
     * 包括DuggeeToken和配对代币的费用
     */
    function withdrawFees() external onlyOwner {
        // 提取DuggeeToken费用
        if (duggeeTokenFeeBalance > 0) {
            uint256 duggeeFees = duggeeTokenFeeBalance;
            duggeeTokenFeeBalance = 0;  // 先清零再转账，防止重入攻击
            require(duggeeToken.transfer(msg.sender, duggeeFees), "DuggeeToken fee transfer failed");
        }

        // 提取配对代币费用
        if (tokenFeeBalance > 0) {
            uint256 tokenFees = tokenFeeBalance;
            tokenFeeBalance = 0;  // 先清零再转账，防止重入攻击
            require(token.transfer(msg.sender, tokenFees), "Token fee transfer failed");
        }
    }
}