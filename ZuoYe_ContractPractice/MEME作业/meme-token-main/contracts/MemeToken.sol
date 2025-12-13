// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract MemeToken is ERC20, Ownable {
    //常量
    uint256 public constant TOTAL_SUPPLY = 1000 * 10 ** 18; // 1000 枚
    uint256 public constant BUY_TAX_RATE = 5; // 买入税率 5%
    uint256 public constant SELL_TAX_RATE = 8; // 卖出税率 8%
    uint256 private constant RATE_PRECISION = 100; // 分母为 100，表示百分比

    uint256 public constant MARKETING_SHARE = 50; // 营销钱包比例 50%
    uint256 public constant LIQUIDITY_SHARE = 50; // 自动添加流动性 50%

    uint256 public constant COOLDOWN_SECONDS = 5; //每次卖出后需等待 5 秒才能再次卖出
    bool public swapAndLiquifyEnabled = true; // 是否开启自动将税费转为流动性的功能

    //变量
    address public marketingWallet; // 营销钱包地址
    IUniswapV2Router02 public uniswapV2Router; // Uniswap V2 路由器
    address public uniswapV2Pair; // 交易对地址 (MemeToken/WETH)

    bool private inSwapAndLiquify; // 防止重入锁
    uint256 public maxTxAmount; // 单笔最大交易额度
    mapping(address => bool) public isExcludedFromTax; // 免税地址列表
    mapping(address => uint256) private _lastSellTime; // 记录每个地址最后一次卖出时间

    //事件
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);
    event MarketingWalletChanged(address wallet);
    event MaxTransactionAmountUpdated(uint256 amount);
    event SwapAndLiquifyFailure(string step, string reason);
    event AddLiquidityFailure(string step, string reason);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    //构造函数
    constructor(address routerAddress, address marketingWalletAddr) ERC20('MyMeme', 'LMEME') Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY); //铸币并转给owner
        marketingWallet = marketingWalletAddr; //设置营销钱包地址

        //设置 uniswap 路由、交易对
        IUniswapV2Router02 _router = IUniswapV2Router02(routerAddress);
        uniswapV2Router = _router;
        uniswapV2Pair = IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH());

        maxTxAmount = TOTAL_SUPPLY / 10; //单笔最大交易：总供应量的 10%

        // 设置免税地址
        isExcludedFromTax[address(this)] = true; // 本合约
        isExcludedFromTax[msg.sender] = true; // 部署者
        isExcludedFromTax[address(0)] = true; // 零地址
        isExcludedFromTax[uniswapV2Pair] = true; // 交易对
        isExcludedFromTax[address(uniswapV2Router)] = true; // 路由器

        // 授权路由器无限使用本代币
        _approve(address(this), address(uniswapV2Router), type(uint256).max);
    }

    //添加初始流动性
    function addInitialLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner {
        require(tokenAmount > 0 && ethAmount > 0, 'Amounts must be greater than zero');
        require(address(this).balance >= ethAmount, 'Not enough ETH in contract');
        require(balanceOf(msg.sender) >= tokenAmount, 'Not enough tokens');

        // 转移代币到合约
        _transfer(msg.sender, address(this), tokenAmount);

        // 授权路由器使用代币
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // 设置滑点容忍度  1%
        uint256 minTokenAmount = (tokenAmount * 99) / 100; // 99% of tokenAmount
        uint256 minETHAmount = (ethAmount * 99) / 100; // 99% of ethAmount

        // 添加流动性
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this), // 代币地址
            tokenAmount, // 代币数量
            minTokenAmount, // 最少代币（滑点）
            minETHAmount, // 最少 ETH
            msg.sender, // 流动性凭证发给谁
            block.timestamp + 300 // 5分钟过期
        );

        // 触发事件
        emit MarketingWalletChanged(marketingWallet);
    }

    //重写ERC20的交易接口
    function _update(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), 'ERC20: transfer from zero address');
        require(recipient != address(0), 'ERC20: transfer to zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');

        //免税账户间的交易，直接转账
        if (isExcludedFromTax[sender] && isExcludedFromTax[recipient]) {
            super._transfer(sender, recipient, amount);
            return;
        }

        //检查单笔交易限额（白名单地址除外）
        require(amount <= maxTxAmount, 'Transfer exceeds max transaction limit');

        //检查交易时间间隔，仅校验用户卖出时
        if (recipient == uniswapV2Pair) {
            require(block.timestamp >= _lastSellTime[sender] + COOLDOWN_SECONDS, 'Please wait for the cooldown period to end.');
            _lastSellTime[sender] = block.timestamp;
        }

        //收税，只有当交易涉及交易对时才收税
        //确定税率
        uint256 taxRate = 0;
        bool isSell = false;
        if (sender == uniswapV2Pair) {
            //交易发送方是交易对，表示用户在从交易对购买Meme代币
            taxRate = BUY_TAX_RATE;
        } else if (recipient == uniswapV2Pair) {
            //交易接收方是交易对，表示用户在向交易对卖出Meme代币
            taxRate = SELL_TAX_RATE;
            isSell = true;
        } else {
            revert('MemeToken: Transfer not allowed outside pair');
        }

        //计算税费
        uint256 tax = (amount * taxRate) / RATE_PRECISION;

        //计算recipient 收到净额
        uint256 recipientAmount = amount - tax;

        //处理税费
        if (tax > 0) {
            //将税费转入合约
            super._transfer(sender, address(this), tax);
            _takeFeeAndLiquify(tax, isSell);
        }

        //给用户转账
        super._transfer(sender, recipient, recipientAmount);
    }

    //处理税费，分离营销费用和流动性添加
    function _takeFeeAndLiquify(uint256 taxAmount, bool isSell) private {
        //计算营销费用和流动性费用
        uint256 marketingTokens = (taxAmount * MARKETING_SHARE) / 100;
        uint256 liquidityTokens = taxAmount - marketingTokens;

        //营销费用转给营销钱包
        super._transfer(address(this), marketingWallet, marketingTokens);

        // 仅在卖出时添加流动性
        if (swapAndLiquifyEnabled && !inSwapAndLiquify && liquidityTokens > 0 && isSell) {
            _swapAndLiquify(liquidityTokens);
        }
    }

    //仅在卖出时添加流动性
    function _swapAndLiquify(uint256 liquidityTokens) private lockTheSwap {
        //将代币的一半兑换为 ETH（WETH）
        uint256 half = liquidityTokens / 2;
        uint256 otherHalf = liquidityTokens - half;

        // 授权路由器使用 half 数量的代币
        _approve(address(this), address(uniswapV2Router), half);

        // 记录合约当前 ETH 余额（用于计算收到多少）
        uint256 initialETHBalance = address(this).balance;

        // 兑换 half 数量的代币为 ETH
        //uint256 minTokenAmount = (half * 90) / 100;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, path, address(this), block.timestamp) {
            // 计算实际兑换得到的 ETH
            uint256 ethReceived = address(this).balance - initialETHBalance;
            //添加流动性
            uint256 minETHAmount = (ethReceived * 90) / 100;
            uint256 minTokenAmount_otehr = (otherHalf * 90) / 100;

            if (ethReceived > 0) {
                //授权router使用 otherHalf 数量的代币
                _approve(address(this), address(uniswapV2Router), otherHalf);

                try
                    uniswapV2Router.addLiquidityETH{value: ethReceived}(
                        address(this), // 代币地址
                        otherHalf, // 代币数量（另一半）
                        minTokenAmount_otehr, // 最少代币（滑点容忍）
                        minETHAmount, // 最少 ETH
                        owner(), // LP 代币发给谁
                        block.timestamp
                    )
                {
                    emit SwapAndLiquify(half, ethReceived, otherHalf);
                } catch Error(string memory reason) {
                    emit AddLiquidityFailure('AddLiquidity failed:', reason);
                }
            }
        } catch Error(string memory reason) {
            emit SwapAndLiquifyFailure('swapExactTokensForETH', reason);
        }

        inSwapAndLiquify = false;
    }

    //swapAndLiquifyEnabled设置
    function updateSwapAndLiquifyEnabled(bool enabled) external onlyOwner {
        swapAndLiquifyEnabled = enabled;
    }

    // 允许合约接收 ETH
    receive() external payable {}
}
