// SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";  // 导入ERC20标准实现
import "@openzeppelin/contracts/access/Ownable.sol";      // 导入所有权管理
import  "./IshibMeme.sol";


contract shibMeme is ERC20,Ownable,IshibMeme{

    // ============ 常量 ============
    ///@dev 基点分母,用于百分比计算(10000=100%)
    uint256 private constant BASIS_POINTS = 10000;
    ///@dev 最大税率25%(2500/10000)  
    uint256 private constant MAX_TAX_RATE = 2500;   
    /// @dev 死亡地址（用于销毁代币）
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;


    // ================uniswap v2============
    /// @dev Uniswap路由合约(不可变)
    IUniswapV2Router02 public immutable uniswapV2Router; 
    /// @dev 交易对地址(不可变)
    address public immutable uniswapV2Pair; 

    // ============税费==============
    /// @dev 买的税费
    uint256 buyTaxRate=500;
    /// @dev 卖的税费
    uint256 sellTaxRate=1000;

    // 税费分配比例(总和=10000=100%)
    uint256 public liquidityShare = 4000;  // 流动性40%
    uint256 public marketingShare = 3000;  // 营销30%
    uint256 public devShare = 2000;        // 开发20%
    uint256 public burnShare = 1000;       // 销毁10%

    address public liquidityTaxwallet;  //接收地址钱包
    address public marketingTaxwallet;
    address public devTaxwallet;

    

    // ============限制==========

    bool public isLimitEnable=true;// 是否开启限制
    uint256 public maxTx;// 单笔交易最大值
    uint256 public maxWalletAmount;// 单个钱包最大值
    
    
    uint256 public coolDownTime=60;// 冷却时间

    /// @dev 记录每个地址的最后交易时间
    mapping(address => uint256) private _lastTransferTime;



    // =============交易=========
    
    bool public tradingEnabled = false;  // 交易是否已启用
    uint256 public tradingEnabledTimestamp;  // 交易启动时间戳
    uint256 public tradingEnabledBlock;      // 交易启动区块号



    // ==============黑名单===========
    mapping(address=>bool) private _isblackList; // 黑名单

    // ==============豁免列表=========

    mapping(address=>bool) private _isExcludedFromFees; // 免税地址
    mapping(address=>bool) private _isExcludedFromLimits; // 免限制地址
    

    // ==============自动流动性=========

    bool private _inSwapAndLiquify; // 是否正在执行swap(防重入)
    uint256 public swapThreshold;    // 触发swap的代币阈值
     /// @dev 是否启用自动添加流动性
    bool public swapAndLiquifyEnabled = true;

    /// @dev 累积的待处理税费
    uint256 private _pendingTaxTokens;


    // ============修饰器=========
    
    /**
     * @dev 防止在swap过程中递归调用
     */

    modifier lockTheSwap {

        _inSwapAndLiquify = true;  // 设置标志为true
        _;  // 执行函数体
        _inSwapAndLiquify = false;  // 恢复标志为false
    }

    // ============ 构造函数 ============

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply, // 总供应量
        address _routerAddress,  // Uniswap路由地址
        address _marketingAddress,
        address _devAddress
    ) ERC20(_name,_symbol) Ownable(msg.sender){

        require(_marketingAddress != address(0), "Marketing wallet cannot be zero");
        require(_devAddress != address(0), "Dev wallet cannot be zero");


        // 初始化Uniswap路由和交易对
        IUniswapV2Router02 _uniswapV2Router=IUniswapV2Router02(_routerAddress);
        address _uniswapV2Pair=IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router=_uniswapV2Router;
        uniswapV2Pair=_uniswapV2Pair;

        // 钱包地址
        liquidityTaxwallet=msg.sender;
        marketingTaxwallet=_marketingAddress;
        devTaxwallet=_devAddress;


        //最大单笔交易金额
        maxTx = _totalSupply * 5/1000; //0.5%
        maxWalletAmount = _totalSupply * 20/1000; //2%
        swapThreshold = _totalSupply * 5 / 10000;   // swap阈值0.05%
    
        
        // 免税地址
        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[DEAD_ADDRESS] = true;
        _isExcludedFromFees[marketingTaxwallet] = true;
        _isExcludedFromFees[devTaxwallet] = true;

        // 免限制地址
        _isExcludedFromLimits[msg.sender] = true;
        _isExcludedFromLimits[address(this)] = true;
        _isExcludedFromLimits[DEAD_ADDRESS] = true;
         _isExcludedFromLimits[_uniswapV2Pair] = true;  // 交易对地址

        // 铸造代币
        _mint(msg.sender,_totalSupply);

    }


    function mint(address to,uint256 amount) external onlyOwner{
        _mint(to,amount);
    }

    // 允许合约接受代币

    receive() external payable{}



    //重写erc20 _update
    /*
     执行顺序：
     * 1. 检查是否为铸造/销毁操作
     * 2. 验证基本条件（金额、黑名单）
     * 3. 检查交易启用状态
     * 4. 应用交易限制（单笔限额、持有量、冷却期）
     * 5. 触发自动流动性添加（如果需要）
     * 6. 计算并收取税费
     * 7. 执行实际转账
    */


    function _update(address from, address to, uint256 amount) internal override {

        //1.筹造和销毁 不需要处理
        if(from == address(0) || to == address(0)){
            super._update(from,to,amount);
            return;
        }

        //2.转账金额必须大于0 
        require(amount>0,"Transfer amount must be greater than zero");
        //3.检查黑名单
        require(!_isblackList[from] && !_isblackList[to],"Blacklisted address");

        //4.owner this跳过所有
        if(from==address(this) || to == address(this)|| from==owner()||to == owner()){
            super._update(from,to,amount);
            return;
        }

        // 5.检查交易是否已启用（防止在正式启动前交易）
        if (!tradingEnabled) {
            require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading not enabled");
        } 


        //【步骤6】应用交易限制（如果启用且双方都不在豁免名单中）
        if(isLimitEnable && !_isExcludedFromLimits[from] && !_isExcludedFromLimits[to]){
            // 1】检查单笔交易限额（防止鲸鱼一次性买卖太多）
            require(amount <= maxTx,"Exceeds max transaction amount");


            // 【6.2】检查最大持有量（只在买入时检查，卖出不限制）
            // to != uniswapV2Pair 表示不是卖出交易（卖出时to是交易对地址）
            if (to != uniswapV2Pair) {
                // 确保接收方持有量不超过最大钱包限额
                require(
                    balanceOf(to) + amount <= maxWalletAmount,
                    "Exceeds max wallet amount"
                );
            }

            // 检查冷却期（防止高频交易/机器人）
            // from != uniswapV2Pair: 不是买入交易（买入不限制冷却）
            if( coolDownTime > 0 && from != uniswapV2Pair){
                require(
                    block.timestamp >= _lastTransferTime[from] + coolDownTime,
                    "Cooldown period active"
                );
                _lastTransferTime[from] = block.timestamp; // 更新最后转账时间

            }   

        }

        

        

        // 【步骤7】自动添加流动性逻辑（在卖出时触发）
        // 判断是否应该执行swap操作的条件：
        bool shouldSwap = !_inSwapAndLiquify &&      // 1. 当前不在swap过程中（防重入）
                          to == uniswapV2Pair &&      // 2. 是卖出交易（to是交易对地址）
                          swapAndLiquifyEnabled &&    // 3. 自动流动性功能已启用
                          _pendingTaxTokens >= swapThreshold; // 4. 累积的税费达到阈值

         if (shouldSwap) {
            _swapAndDistribute(); // 执行swap和分配操作
        }



        // 【步骤8】判断是否需要收取税费
        // 收税条件：
        bool takeFee = !_inSwapAndLiquify && !_isExcludedFromFees[from] && 
                    !_isExcludedFromFees[to] && 
                    (from == uniswapV2Pair || to == uniswapV2Pair);

        uint256 taxAmount=0;
        if(takeFee){
            uint256 taxRate; // 声明税率变量
            if(from==uniswapV2Pair){
                taxRate = buyTaxRate;
            } else{
                taxRate = sellTaxRate;

                // 【8.2】启动保护：前10个区块高税率（99%）防夹子机器人
                // 夹子机器人会在交易启动瞬间抢先交易，高税率可以防止这种行为
                if(tradingEnabledBlock >0 && block.number <=tradingEnabledBlock+10){
                    taxRate = 9900; // 设置为99%的惩罚性税率
                    
                }
            }
            taxAmount = (amount*taxRate)/BASIS_POINTS;
            _pendingTaxTokens += taxAmount; // 累加到待处理税费中


            if(taxAmount>0){
                super._update(from,address(this),taxAmount);
            }

        }
        uint256 transferAmount= amount - taxAmount;
        super._update(from,to,transferAmount); 

        
    }







 // ============ 内部函数 ============


    // 税率分配

    function _swapAndDistribute() private lockTheSwap(){
        uint256 contracttokenbanlance  = _pendingTaxTokens;
        if(contracttokenbanlance==0) return;

        _pendingTaxTokens =0;

        uint256 totalshares = liquidityShare + marketingShare + devShare + burnShare;
        if(totalshares==0) return;


        // 计算各部分份额
        uint256 liquidityTokens = (contracttokenbanlance*liquidityShare)/totalshares;
        uint256 marketingyToken = (contracttokenbanlance*marketingShare)/totalshares;
        uint256 devToken = (contracttokenbanlance*devShare)/totalshares;
        uint256 burnToken = (contracttokenbanlance*burnShare)/totalshares;

        // 销毁代币
        if(burnToken>0){
            super._update(address(this),DEAD_ADDRESS,burnToken);
        }

        // 流动性部分：一半swap成ETH
        uint256 liquidityHalf = liquidityTokens/2;
        uint256 liquidityOtherHalf = liquidityTokens-liquidityHalf;

        // 需要swap成ETH的代币总量
        uint256 tokensToSwap = liquidityHalf + devToken + marketingyToken;
        if(tokensToSwap==0) return;

        // Swap代币为ETH
        uint256 initalEthBanlance = address(this).balance;
        _swapTokensForETH(tokensToSwap);
        uint256 ethReceived = address(this).balance-initalEthBanlance;

        // 计算ETH分配
        uint256 ethForliquidity = (ethReceived * liquidityHalf)/tokensToSwap;
        uint256 ethForMarketing = (ethReceived*marketingyToken)/tokensToSwap;
        uint256 ethFordev= ethReceived - ethForliquidity - ethForMarketing;

        // 添加流动性
        if(liquidityOtherHalf>0 && ethForliquidity>0){
            _addliquidity(liquidityOtherHalf, ethForliquidity);
        }

        // 发送ETH给营销和开发钱包
        if(ethForMarketing > 0){
            payable(marketingTaxwallet).transfer(ethForMarketing);
        }
        if(ethFordev > 0){
            payable(devTaxwallet).transfer(ethFordev);
        }
    }

     /**
     * @dev 将代币swap为ETH
     */
    function _swapTokensForETH(uint256 tokenAmount) private{

        address[] memory path = new address[](2);
        path[0] = address(this);  // 源代币(当前合约)
        path[1] = uniswapV2Router.WETH();  // 目标代币(WETH)

        _approve(address(this),address(uniswapV2Router),tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path, 
            address(this), 
            block.timestamp
        );
    }

    // 添加流动性
    function _addliquidity(uint256 tokenAmount,uint256 ethAmount) private{
        _approve(address(this),address(uniswapV2Router),tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this), 
            tokenAmount, 
            0, 
            0, 
            liquidityTaxwallet, 
            block.timestamp
        );


    }


// ============ 管理员函数 ============

    // 设置税率

    function setTaxRates(uint256 _buyTax,uint256 _sellTax) external override onlyOwner{

        require(_buyTax<=MAX_TAX_RATE, "Buy tax too high");
        require(_sellTax<=MAX_TAX_RATE, "Buy tax too high");


        buyTaxRate = _buyTax;
        sellTaxRate = _sellTax;
    }


     /**
     * @dev 设置税费分配比例
     */
    function setTaxDistribution(
        uint256 _liquidityShare,
        uint256 _marketingShare,
        uint256 _devShare,
        uint256 _burnShare
    ) external override onlyOwner{


         // 确保总和为100%(10000基点)
        require(
            _liquidityShare + _marketingShare + _devShare + _burnShare == BASIS_POINTS,
            "Shares must sum to 10000"
        );

        liquidityShare = _liquidityShare;
        marketingShare = _marketingShare;
        devShare = _devShare;
        burnShare = _burnShare;
                    
        

    }

    /**
     * @dev 设置税费钱包
     */
    function setTaxwallet(
        address _liquidityTaxwallet,
        address _marketingTaxwallet,
        address _devTaxwallet
    ) external override onlyOwner{


        require(_liquidityTaxwallet!=address(0),"Invalid liquidity wallet address");
        require(_marketingTaxwallet!=address(0),"Invalid liquidity wallet address");
        require(_devTaxwallet!=address(0),"Invalid liquidity wallet address");

        liquidityTaxwallet=_liquidityTaxwallet;
        marketingTaxwallet= _marketingTaxwallet;
        devTaxwallet=_devTaxwallet;

    }


   

    /**
     * @dev 设置交易限制
     */
    function setLimits(uint256 _maxTxAmount, uint256 _maxWalletAmount) external override onlyOwner{
        require(_maxTxAmount >= totalSupply() / 1000, "max tx too low");
        require(_maxWalletAmount >= totalSupply() / 100, "Max wallet too low");
        maxTx=_maxTxAmount;
        maxWalletAmount=_maxWalletAmount;
    }

    // 是/否启动限制
    function setLimitEnable(bool _enabled)external override onlyOwner{
        isLimitEnable=_enabled;
    }
    // 设置冷却时间
    function setCooldownTime(uint256 _time)external override onlyOwner{
        coolDownTime=_time;
    }

    function enableTrading() external override onlyOwner{
        require(!tradingEnabled,"Trading already enabled");
        tradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
        tradingEnabledBlock = block.number;


    }


     /**
     * @dev 设置swap阈值
     */
    function setSwapThreshold(uint256 threshold) external override onlyOwner {
        require(threshold >= totalSupply() / 100000, "Threshold too low"); // 至少0.001%
        swapThreshold = threshold;
    }

    /**
     * @dev 设置是否启用自动流动性
     */
    function setSwapAndLiquifyEnabled(bool enabled) external onlyOwner {
        swapAndLiquifyEnabled = enabled;
    }

     // 黑名单
    function setBlackAddress(address _address,bool is_black)external override onlyOwner{
        require(_address != address(0), "Cannot blacklist contract");
        require(_address != owner(), "Cannot blacklist owner");
        _isblackList[_address]=is_black;

    }




    // 免税务地址
     function setExcludedFromFees(address _address,bool _excluded) external override onlyOwner{
        require(_address!=address(0),"Invalid liquidity wallet address");
        _isExcludedFromFees[_address]=_excluded;

    
    }
    // 免限制地址
    function setExcludedFromLimits( address _address,bool _excluded) external override onlyOwner{
        _isExcludedFromLimits[_address]=_excluded;
    }

    /** 
     *  @dev 手动触发swap和流动性添加
    */

    /** 
     *  @dev 紧急提取卡在合约中的ETH
    */

      /** 
     *  @dev 紧急提取卡在合约中的代币
    */
    
    // ============ 查询函数 ============
    //    查询税率
    function getTaxRates() external view returns(uint256 _buyTax, uint256 _sellTax){
        return (buyTaxRate,sellTaxRate);
    }
        
    /**
        @dev 查询分配
     */
    function getTaxDistribution()external view returns(
        uint256 _liquidityShare,
        uint256 _marketingShare,
        uint256 _devShare,
        uint256 _burnShare
    ){
        return (liquidityShare,marketingShare,devShare,burnShare);
    }
    /**
        @dev 查询限制

     */
     function getLimits() external view override returns (
        uint256 _maxTxAmount,
        uint256 _maxWalletAmount,
        uint256 _cooldownPeriod
    ) {
        return (maxTx, maxWalletAmount, coolDownTime);
    }

    //  查询黑名单
    function isBlacklisted(address account) external view override returns (bool) {
        return _isblackList[account];
    }

   
    // 查询免税
     function isExcludedFromFees(address account) external view override returns (bool) {
        return _isExcludedFromFees[account];
    }
    // 查询税费累计
    function getPendingTaxTokens() external view returns (uint256) {
        return _pendingTaxTokens;
    }







}

// ============ Uniswap V2 接口定义 ============

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidityETH(
        address token,  // 要添加的代币合约地址
        uint amountTokenDesired,// 要添加的代币数量
        uint amountTokenMin,// 最小代币数量
        uint amountETHMin,// 最小ETH数量
        address to,// 接收者地址
        uint deadline// 交易过期时间
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}


