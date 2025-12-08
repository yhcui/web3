// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

/**
 * @title ShibaMemeCoin
 * @dev SHIB风格的MEME代币合约，实现代币税、流动性池集成和交易限制功能
 */
contract ShibaMemeCoin is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // 基础参数配置
    uint256 private constant MAX_SUPPLY = 1_000_000_000_000_000 * 10**18; // 1000万亿枚
    uint256 private constant INITIAL_SUPPLY = MAX_SUPPLY;

    // 税费配置
    struct TaxRates {
        uint256 buyTax;          // 买入税费
        uint256 sellTax;         // 卖出税费
        uint256 transferTax;     // 转账税费
        uint256 liquidityFee;    // 流动性费用
        uint256 reflectionFee;   // 反射奖励费用
        uint256 burnFee;         // 销毁费用
        uint256 marketingFee;    // 营销费用
    }

    TaxRates public taxRates;

    // 交易限制配置
    struct TradingLimits {
        uint256 maxTransactionAmount;    // 最大交易量
        uint256 maxWalletAmount;         // 最大持有量
        uint256 minTimeBetweenTx;        // 交易间隔时间
        bool limitsInEffect;             // 限制是否生效
    }

    TradingLimits public tradingLimits;

    // 地址配置
    address public marketingWallet;
    address public liquidityWallet;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    // Uniswap配置
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    // 状态变量
    bool public tradingEnabled = false;
    bool public swapEnabled = false;
    bool private inSwap = false;
    uint256 public swapThreshold;

    // 映射
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => uint256) public lastTransactionTime;
    mapping(address => bool) public isBlacklisted;

    // 反射机制变量
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = INITIAL_SUPPLY;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => bool) private _isExcludedFromReward;
    address[] private _excludedFromReward;

    // 事件定义
    event TradingEnabled(bool enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    event TaxRatesUpdated(TaxRates newRates);
    event TradingLimitsUpdated(TradingLimits newLimits);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeFromLimits(address indexed account, bool isExcluded);
    event AutomatedMarketMakerPairUpdated(address indexed pair, bool indexed value);
    event MarketingWalletUpdated(address indexed newWallet);
    event LiquidityWalletUpdated(address indexed newWallet);
    event Blacklisted(address indexed account, bool isBlacklisted);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        address _marketingWallet,
        address _liquidityWallet,
        address _router
    ) ERC20("ShibaMemeCoin", "SMEME") {
        // 初始化钱包地址
        marketingWallet = _marketingWallet;
        liquidityWallet = _liquidityWallet;

        // 初始化Uniswap路由
        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());

        // 设置自动化做市商对
        _setAutomatedMarketMakerPair(uniswapV2Pair, true);

        // 初始化税费配置（基础税率，单位：基点，10000 = 100%）
        taxRates = TaxRates({
            buyTax: 500,         // 5% 买入税
            sellTax: 800,        // 8% 卖出税
            transferTax: 200,    // 2% 转账税
            liquidityFee: 200,   // 2% 流动性费用
            reflectionFee: 300,  // 3% 反射奖励
            burnFee: 100,        // 1% 销毁费用
            marketingFee: 400    // 4% 营销费用
        });

        // 初始化交易限制
        tradingLimits = TradingLimits({
            maxTransactionAmount: INITIAL_SUPPLY.mul(1).div(100),  // 1% 最大交易量
            maxWalletAmount: INITIAL_SUPPLY.mul(2).div(100),       // 2% 最大持有量
            minTimeBetweenTx: 30,                                  // 30秒交易间隔
            limitsInEffect: true
        });

        // 设置交换阈值
        swapThreshold = INITIAL_SUPPLY.mul(5).div(10000); // 0.05%

        // 免除费用和限制
        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[marketingWallet] = true;
        isExcludedFromFees[liquidityWallet] = true;
        isExcludedFromFees[deadAddress] = true;

        isExcludedFromLimits[owner()] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[marketingWallet] = true;
        isExcludedFromLimits[liquidityWallet] = true;
        isExcludedFromLimits[deadAddress] = true;

        // 初始化反射机制
        _rOwned[owner()] = _rTotal;

        // 铸造初始供应量给合约部署者
        _mint(owner(), INITIAL_SUPPLY);

        emit Transfer(address(0), owner(), INITIAL_SUPPLY);
    }

    // 接收ETH
    receive() external payable {}

    /**
     * @dev 启用/禁用交易
     */
    function enableTrading(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
        swapEnabled = _enabled;
        emit TradingEnabled(_enabled);
    }

    /**
     * @dev 更新税费配置
     */
    function updateTaxRates(TaxRates calldata _taxRates) external onlyOwner {
        require(_taxRates.buyTax <= 1000, "Buy tax too high"); // 最大10%
        require(_taxRates.sellTax <= 1500, "Sell tax too high"); // 最大15%
        require(_taxRates.transferTax <= 500, "Transfer tax too high"); // 最大5%

        taxRates = _taxRates;
        emit TaxRatesUpdated(_taxRates);
    }

    /**
     * @dev 更新交易限制
     */
    function updateTradingLimits(TradingLimits calldata _limits) external onlyOwner {
        require(_limits.maxTransactionAmount >= INITIAL_SUPPLY.mul(1).div(1000), "Max tx too low"); // 至少0.1%
        require(_limits.maxWalletAmount >= INITIAL_SUPPLY.mul(5).div(1000), "Max wallet too low"); // 至少0.5%

        tradingLimits = _limits;
        emit TradingLimitsUpdated(_limits);
    }

    /**
     * @dev 设置免除费用状态
     */
    function excludeFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    /**
     * @dev 设置免除限制状态
     */
    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
        emit ExcludeFromLimits(account, excluded);
    }

    /**
     * @dev 设置自动化做市商对
     */
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "Cannot remove main pair");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        emit AutomatedMarketMakerPairUpdated(pair, value);
    }

    /**
     * @dev 更新营销钱包
     */
    function updateMarketingWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Cannot be zero address");
        marketingWallet = newWallet;
        emit MarketingWalletUpdated(newWallet);
    }

    /**
     * @dev 更新流动性钱包
     */
    function updateLiquidityWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Cannot be zero address");
        liquidityWallet = newWallet;
        emit LiquidityWalletUpdated(newWallet);
    }

    /**
     * @dev 设置黑名单
     */
    function blacklist(address account, bool blacklisted) external onlyOwner {
        isBlacklisted[account] = blacklisted;
        emit Blacklisted(account, blacklisted);
    }

    /**
     * @dev 手动触发代币交换和流动性添加
     */
    function manualSwapAndLiquify() external onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        require(contractTokenBalance > 0, "No tokens to swap");
        _swapAndLiquify(contractTokenBalance);
    }

    /**
     * @dev 紧急提取ETH
     */
    function emergencyWithdrawETH() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to withdraw");

        payable(owner()).transfer(ethBalance);
    }

    /**
     * @dev 紧急提取代币
     */
    function emergencyWithdrawTokens(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(this), "Cannot withdraw own tokens");

        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to withdraw");

        token.transfer(owner(), tokenBalance);
    }

    /**
     * @dev 重写transfer函数以实现费用和限制机制
     */
    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(!isBlacklisted[from] && !isBlacklisted[to], "Blacklisted address");

        // 检查交易是否启用
        if (!tradingEnabled) {
            require(isExcludedFromFees[from] || isExcludedFromFees[to], "Trading not enabled");
        }

        // 应用交易限制
        if (tradingLimits.limitsInEffect) {
            _applyTradingLimits(from, to, amount);
        }

        // 执行代币交换和流动性添加
        if (
            swapEnabled &&
            !inSwap &&
            !automatedMarketMakerPairs[from] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to] &&
            balanceOf(address(this)) >= swapThreshold
        ) {
            _swapAndLiquify(swapThreshold);
        }

        // 计算税费
        bool takeFee = !inSwap;
        if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        if (takeFee) {
            fees = _calculateFees(from, to, amount);
            if (fees > 0) {
                super._transfer(from, address(this), fees);
                amount = amount.sub(fees);
            }
        }

        super._transfer(from, to, amount);
    }

    /**
     * @dev 应用交易限制
     */
    function _applyTradingLimits(address from, address to, uint256 amount) private {
        // 最大交易量限制
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(amount <= tradingLimits.maxTransactionAmount, "Exceeds max transaction amount");
        }

        // 最大持有量限制
        if (!isExcludedFromLimits[to]) {
            require(
                balanceOf(to).add(amount) <= tradingLimits.maxWalletAmount,
                "Exceeds max wallet amount"
            );
        }

        // 交易时间间隔限制
        if (
            !isExcludedFromLimits[from] &&
            tradingLimits.minTimeBetweenTx > 0 &&
            automatedMarketMakerPairs[to]
        ) {
            require(
                block.timestamp >= lastTransactionTime[from].add(tradingLimits.minTimeBetweenTx),
                "Transaction too frequent"
            );
            lastTransactionTime[from] = block.timestamp;
        }
    }

    /**
     * @dev 计算交易费用
     */
    function _calculateFees(address from, address to, uint256 amount) private view returns (uint256) {
        uint256 taxRate = 0;

        if (automatedMarketMakerPairs[from]) {
            // 买入交易
            taxRate = taxRates.buyTax;
        } else if (automatedMarketMakerPairs[to]) {
            // 卖出交易
            taxRate = taxRates.sellTax;
        } else {
            // 转账交易
            taxRate = taxRates.transferTax;
        }

        return amount.mul(taxRate).div(10000);
    }

    /**
     * @dev 执行代币交换和流动性添加
     */
    function _swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // 计算各部分份额
        uint256 totalFees = taxRates.liquidityFee.add(taxRates.marketingFee).add(taxRates.burnFee);
        if (totalFees == 0) return;

        uint256 liquidityTokens = contractTokenBalance.mul(taxRates.liquidityFee).div(totalFees).div(2);
        uint256 marketingTokens = contractTokenBalance.mul(taxRates.marketingFee).div(totalFees);
        uint256 burnTokens = contractTokenBalance.mul(taxRates.burnFee).div(totalFees);
        uint256 swapTokens = contractTokenBalance.sub(liquidityTokens).sub(burnTokens);

        // 销毁代币
        if (burnTokens > 0) {
            super._transfer(address(this), deadAddress, burnTokens);
        }

        // 交换代币为ETH
        uint256 initialETHBalance = address(this).balance;
        _swapTokensForEth(swapTokens);
        uint256 newETHBalance = address(this).balance.sub(initialETHBalance);

        // 分配ETH
        uint256 ethForLiquidity = newETHBalance.mul(taxRates.liquidityFee).div(totalFees.sub(taxRates.burnFee)).div(2);
        uint256 ethForMarketing = newETHBalance.sub(ethForLiquidity);

        // 添加流动性
        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            _addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(liquidityTokens, ethForLiquidity, liquidityTokens);
        }

        // 发送营销费用
        if (ethForMarketing > 0) {
            payable(marketingWallet).transfer(ethForMarketing);
        }
    }

    /**
     * @dev 交换代币为ETH
     */
    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev 添加流动性
     */
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
    }

    /**
     * @dev 获取代币信息
     */
    function getTokenInfo() external view returns (
        uint256 totalSupply_,
        uint256 circulatingSupply,
        uint256 burnedTokens,
        uint256 contractBalance,
        bool tradingEnabled_,
        bool swapEnabled_
    ) {
        totalSupply_ = totalSupply();
        circulatingSupply = totalSupply_.sub(balanceOf(deadAddress));
        burnedTokens = balanceOf(deadAddress);
        contractBalance = balanceOf(address(this));
        tradingEnabled_ = tradingEnabled;
        swapEnabled_ = swapEnabled;
    }

    /**
     * @dev 获取费用信息
     */
    function getFeeInfo() external view returns (TaxRates memory) {
        return taxRates;
    }

    /**
     * @dev 获取限制信息
     */
    function getLimitInfo() external view returns (TradingLimits memory) {
        return tradingLimits;
    }
}