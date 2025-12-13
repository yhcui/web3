// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";

/**
 * @title DuggeeToken - SHIB风格的Meme代币合约
 * @dev 这是一个基于ERC20标准的Meme代币，实现了交易税、流动性池集成和交易限制功能
 *
 * 主要功能特性：
 * 1. 代币税功能：对每笔代币交易征收一定比例的税费，税费分配给合约所有者
 * 2. 流动性池集成：可与流动性池合约进行交互，支持添加和移除流动性
 * 3. 交易限制功能：设置单笔交易最大额度和每日交易次数限制，防止恶意操纵市场
 *
 */
contract DuggeeToken is ERC20, Ownable {

    // ========== 状态变量 ==========

    /**
     * @dev 交易税百分比
     * 默认设置为5%，表示每笔交易将征收5%的税费
     * 税费将自动转账给合约所有者
     */
    uint256 public taxPercentage = 5;

    /**
     * @dev 单笔交易最大额度
     * 默认设置为1000个代币（考虑18位小数）
     * 用于防止大额交易对市场造成冲击
     */
    uint256 public maxTxAmount = 1000 * 10**18;

    /**
     * @dev 每日交易次数限制
     * 默认设置为10次，防止单个地址频繁交易
     * 用于维护市场稳定，防止机器人交易
     */
    uint8 public dailyTxLimit = 10;

    /**
     * @dev 记录每个地址的每日交易次数
     * key: 用户地址, value: 当日交易次数
     */
    mapping(address => uint256) public dailyTxCount;

    /**
     * @dev 记录每个地址最后交易的时间戳（以天为单位）
     * key: 用户地址, value: 最后交易日期（以天为单位的Unix时间戳）
     * 用于判断是否需要重置每日交易计数器
     */
    mapping(address => uint256) public lastTxDay;
    /**
     * @dev uniswapv2 地址
     */
    UniswapV2Router02 public immutable router;
    // ========== 构造函数 ==========

    /**
     * @dev 构造函数
     * @param initialSupply 代币初始供应量（包含18位小数）
     *
     * 功能：
     * 1. 初始化ERC20代币基本信息（名称：DuggeeToken，符号：DUG）
     * 2. 设置合约部署者为所有者
     * 3. 将初始供应量铸造给合约部署者
     */
    constructor(address unswaipRouter2Address, uint256 initialSupply) ERC20("DuggeeToken", "DUG") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
        router = UniswapV2Router02(unswaipRouter2Address);
    }

    // ========== 事件 ==========

    /**
     * @dev 已征税转账事件
     * 当用户转账时触发此事件，记录实际转账金额和征税金额
     *
     * @param from 转账发起地址
     * @param to 转账接收地址
     * @param value 扣除税费后的实际转账金额
     * @param tax 征收的税费金额
     */
    event TransferTaxed(address indexed from, address indexed to, uint256 value, uint256 tax);

    // ========== 代币转账功能 ==========

    /**
     * @dev 重写ERC20的transfer方法，实现交易税和交易限制
     *
     * 流程：
     * 1. 调用_beforeTokenTransfer检查交易限制
     * 2. 计算交易税费
     * 3. 分别将税费转账给合约所有者，剩余金额转账给接收者
     * 4. 触发TransferTaxed事件
     *
     * @param to 接收地址
     * @param value 转账金额
     * @return bool 转账是否成功
     */
    function transfer(address to, uint256 value) public override returns (bool) {
        address sender = _msgSender();
        _beforeTokenTransfer(sender, value);  // 检查交易限制

        // 计算税费：税额 = 转账金额 × 税率%
        uint256 taxAmount = (value * taxPercentage) / 100;
        uint256 amountAfterTax = value - taxAmount;

        // 先将税费转账给合约所有者
        _transfer(sender, super.owner(), taxAmount);
        // 再将剩余金额转账给接收者
        _transfer(sender, to, amountAfterTax);

        // 触发已征税转账事件
        emit TransferTaxed(sender, to, amountAfterTax, taxAmount);
        return true;
    }

    /**
     * @dev 重写ERC20的transferFrom方法，实现交易税和交易限制
     *
     * 流程：
     * 1. 检查交易限制
     * 2. 花费授权额度（注意：花费全部value，包括税费）
     * 3. 计算税费并分别转账
     * 4. 触发事件
     *
     * @param from 代币来源地址
     * @param to 代币接收地址
     * @param value 转账金额
     * @return bool 转账是否成功
     */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _beforeTokenTransfer(from, value);  // 检查交易限制

        // 计算税费
        uint256 taxAmount = (value * taxPercentage) / 100;
        uint256 amountAfterTax = value - taxAmount;

        // 花费授权额度（注意：这里消耗全部value，包括税费部分）
        _spendAllowance(from, _msgSender(), value);

        // 分别转账：税费给所有者，剩余金额给接收者
        _transfer(from, super.owner(), taxAmount);
        _transfer(from, to, amountAfterTax);

        // 触发已征税转账事件
        emit TransferTaxed(from, to, amountAfterTax, taxAmount);
        return true;
    }

    // ========== 交易限制检查功能 ==========

    /**
     * @dev 交易前检查交易限制的内部函数
     *
     * 检查项目：
     * 1. 排除铸币操作（from != address(0)）和所有者操作
     * 2. 单笔交易金额不能超过maxTxAmount限制
     * 3. 每日交易次数不能超过dailyTxLimit限制
     * 4. 自动重置每日交易计数器（如果跨天）
     *
     * @param from 发送地址
     * @param value 交易金额
     */
    function _beforeTokenTransfer(address from, uint256 value) internal {
        // 排除铸币操作和所有者操作，这些不受交易限制
        if (from != address(0) && from != owner()) {
            // 检查单笔交易金额限制
            require(value <= maxTxAmount, "more than max tx amount");

            // 获取当前日期（以天为单位）
            uint256 currentDay = getCurrentDay();

            // 如果是新的交易日期，重置交易计数器
            if (lastTxDay[from] < currentDay) {
                dailyTxCount[from] = 0;
                lastTxDay[from] = currentDay;
            }

            // 增加交易次数并检查每日交易限制
            dailyTxCount[from] += 1;
            require(dailyTxCount[from] <= dailyTxLimit, "exceeds daily transaction limit");
        }
    }

    // ========== 管理员功能 ==========

    /**
     * @dev 设置单笔交易最大额度（仅所有者）
     *
     * @param newMaxTxAmount 新的单笔交易最大额度
     */
    function setMaxTxAmount(uint256 newMaxTxAmount) external onlyOwner {
        maxTxAmount = newMaxTxAmount;
    }

    /**
     * @dev 获取当前日期（以天为单位）
     *
     * 计算方式：将当前区块时间戳除以一天的秒数
     * 用于判断是否需要重置每日交易计数器
     *
     * @return uint256 当前日期（从1970年1月1日开始的天数）
     */
    function getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /**
     * @dev 设置交易税百分比（仅所有者）
     *
     * 注意：税率建议设置为合理范围（0-20%），过高的税率会影响用户体验
     *
     * @param newTaxPercentage 新的交易税百分比
     */
    function setTaxPercentage(uint256 newTaxPercentage) external onlyOwner {
        taxPercentage = newTaxPercentage;
    }
    

    function addLiquidity(uint amount, uint amountMin, 
        address token, uint tokenAmount, uint tokenAmountMin
    ) external {
        require(transferFrom(msg.sender, address(this), amount), "token transfer fail");
        approve(address(router), amount);
        
        IERC20 erc20Token = IERC20(token);
        require(erc20Token.transferFrom(msg.sender, address(this), tokenAmount), "token transfer fail");
        erc20Token.approve(address(router), tokenAmount);

        router.addLiquidityETH(
            address(this),
            token,
            amount,
            tokenAmount,
            amountMin,
            tokenAmountMin,
            msg.sender,
            block.timestamp + 10 minutes
        );
    }

}