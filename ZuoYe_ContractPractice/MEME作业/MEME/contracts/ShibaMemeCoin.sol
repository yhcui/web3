// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// IUniswapV2Factory 是 “管理者” 和 “记录员”，负责创建和跟踪所有的交易对（流动性池）
interface IUniswapV2Factory {
    // 这里的TokenB是WETH,也就是交易对是代币和WETH,router中再进行WETH和ETH的转换
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

// IUniswapV2Router02 是 “执行者” 和 “交易前台”，负责执行用户和合约发起的代币交换、流动性添加/移除等操作。
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    /*
        ETH 是以太坊网络的原生货币，它不是一个标准的 ERC-20 代币，因此无法直接与遵循 ERC-20 标准的 SMEME 代币在 Uniswap V2 这样的 DEX 中配对交易。
        MEME -> WETH -> ETH
        路由器需要 WETH 地址来构建 Token -> ETH 的交换路径，即 [TokenAddress, WETHAddress]。
        路由器必须调用 WETH 合约的 deposit() 和 withdraw() 函数来完成 ETH -> WETH 的自动包裹和解包。

    */
    function WETH() external pure returns (address);
    /*
    这个方法的目的是允许用户或合约：
    1、出售 精确数量的 ERC-20 代币（在本例中是 SMEME）。
    2、换取 另一种资产，最终目标是 ETH（或 WETH）。

    部分名称,含义
    swapExactTokens,意味着 发送的代币数量 是精确指定的 (amountIn)。
    ForETH,意味着交易的最终输出是 原生 ETH。
    SupportingFeeOnTransferTokens,意味着这个方法能够正确处理在转账过程中会被扣税的代币。

    为什么需要这个特殊的方法？
        对于大多数标准 ERC-20 代币，Uniswap V2 使用 swapExactTokensForETH。
        然而，对于您的 SMEME 代币：合约打算发送 100 个 SMEME 代币去交换 ETH。
        在转账 100 个代币给 Uniswap Pair 时，代币合约（SMEME）会收取 8\% 的卖出税。
        结果： Uniswap Pair 实际只收到了 92 个代币。
        如果使用标准方法，Uniswap 会基于接收 100 个代币的预期来计算价格和滑点，导致交易失败或价格不准确。
        SupportingFeeOnTransferTokens 解决了这个问题： 它告诉 Uniswap Router，它预期接收的数量（100）和实际收到的数量（92）是不同的。
        Router 会在内部调整逻辑，确保交易基于实际收到的数量来执行，从而成功完成代币交换。

    swapExactTokensForETHSupportingFeeOnTransferTokens 方法只是接收已经被扣除税费的代币。

    */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, // 要发送的 SMEME 代币数量 (swapTokens) -- 已经被扣除税费
        uint amountOutMin, // amountOutMin: 要求的最低 ETH 数量 (这里设为 0，因为是内部调用)
        address[] calldata path, // [SMEME 地址, WETH 地址]
        address to, // ETH 接收地址 (合约地址本身)
        uint deadline // 交易截止时间
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

// 简要说明：下面定义了与 Uniswap V2 相关的接口，合约通过这些接口
// 与去中心化交易所路由和工厂进行交互（创建交易对、兑换、添加流动性等）。

/**
 * @title ShibaMemeCoin
 * @dev SHIB风格的MEME代币合约，实现代币税、流动性池集成和交易限制功能
 */

/*

基于转账方向的识别是所有税费/反射型代币合约的通用机制。
交易类型	    发送方 (from)	             接收方 (to)	            适用税率
买入 (Buy)	    uniswapV2Pair (AMM 池)	    用户的钱包地址	            taxRates.buyTax
卖出 (Sell)	    用户的钱包地址	             uniswapV2Pair (AMM 池)	    taxRates.sellTax
转账 (Transfer)	钱包A	                    钱包 B	                    taxRates.transferTax
一、“买入”（Buy）
“买入”（Buy）这个操作，是从用户在去中心化交易所（DEX），如 Uniswap 或 SushiSwap 上进行交易时体现的，而非直接调用代币合约本身的方法
在以太坊或 EVM 兼容链上的 DeFi 生态中，用户“买入”代币的完整链上流程如下：

1. 外部操作：通过 DEX 路由
用户在 DEX 界面上执行“用 ETH 换取 SMEME”的操作。DEX 的底层协议（如 Uniswap V2）会执行一个核心操作：与流动性池（Pair 合约）进行交互。

2. 链上触发：AMM Pair 的 swap() 函数
用户交易触发了 Uniswap V2 的 Pair 合约（即 uniswapV2Pair）中的 swap() 函数。这个 Pair 合约（流动性池）执行的动作是：
    从用户的钱包中接收 ETH。
    将池子中持有的 SMEME 代币，转账 给用户。

3. 合约识别：_transfer 的触发
正是这个 “将 SMEME 代币转账给用户” 的步骤，触发了 ShibaMemeCoin 合约的 ERC-20 核心函数：_transfer(address from, address to, uint256 amount)。
    from 地址： 此时是 Uniswap 的 Pair 合约地址 (uniswapV2Pair)。
    to 地址： 此时是买入代币的用户地址

4. 业务逻辑：买入税的计算

二、“卖出”（Sell）
卖出与卖入相反。to 地址： 此时是 Uniswap 的Pair 合约地址 (uniswapV2Pair)。
三、“转账”（Transfer）

四、“其他”（Others）


五、这个合约为什么只有添加流动性，没有移除流动性？
这种类型的 Meme Coin 合约，其自动流动性机制 (_addLiquidity) 将获得的 LP Token（流动性提供者代币）发送给了项目方控制的地址：liquidityWallet

业务逻辑：确保流动性安全
    目的： 如果合约内提供了移除流动性的函数，并且这些流动性是由项目方钱包持有的，那么项目方可以直接调用合约来“撤池”（Rug Pull），拿走池子里的 ETH 和代币。
    安全保障： 通过不提供移除流动性的功能，并由外部项目方钱包持有 LP Token，项目方可以向社区承诺（或通过锁定 LP Token 的方式），这些自动添加的流动性是永久性的，不会被轻易撤走。

如何移除流动性？
    由于 LP Token 被发送到了 liquidityWallet，只有持有该钱包私钥的人，才能通过直接与 Uniswap Router 合约交互来移除这部分流动性。 这不是代币合约本身的功能。

 用户如何移除流动性？
如果是用户手动通过传统方式添加的流动性（非合约自动添加），那么他们会收到 LP Token。
移除方式： 用户必须直接前往 Uniswap 或其他 DEX 的界面，使用他们钱包中持有的 LP Token，调用 Uniswap Router 合约的 removeLiquidityETH 或其他相关方法来撤回他们的资金。

唯一的“移除”相关的函数
    在合约中，唯一与资金撤出相关的函数是紧急提款函数，但它们不是移除流动性：
    emergencyWithdrawETH(): 提取合约地址中积累的游离 ETH（通常是 Uniswap 交换代币后留下的）。
    emergencyWithdrawTokens(address tokenAddress): 提取合约地址中意外或错误发送的其他 ERC-20 代币。
    这两个函数都无法触及或移除 Uniswap 流动性池中的资产。

六、凭将 LP Token 发送到 liquidityWallet 这一行为，并不能保证流动性是安全的。为什么项目方依然这样做？以及如何实现安全目的？
1. 方便后续的流动性锁定（Liquidity Locking）
   仅仅将 LP Token 放入一个钱包地址，项目方随时都可以用私钥来提取。为了实现“永久性”流动性的目的，项目方必须执行一个额外的、至关重要的步骤：锁定流动性。
机制	            描述	                                                                                   安全性
转移 LP Token	    将 liquidityWallet 中持有的 LP Token 转移到 时间锁定智能合约 中（如 PinkLock、UniCrypt 等）。	高：一旦锁定，即使项目方也无法在预定时间（例如 1 年或 5 年）到期前提取流动性。
发送到销毁地址	     将 liquidityWallet 中持有的 LP Token 转移到 销毁地址 (0x...dEaD)。	                          最高：LP Token 被永久销毁，流动性被永远锁定在池子中，不可撤回。
2. 为什么不直接在合约内锁定？
技术上，合约可以将 LP Token 直接发送给时间锁定合约，但实际操作中通常需要 liquidityWallet 作为中转：
    灵活性： 预留 liquidityWallet 可以让项目方灵活选择使用哪种锁定服务（不同的锁定合约有不同的地址和功能）。
    初始控制： 在项目启动的极短时间内，可能需要 liquidityWallet 临时控制 LP Token，以便在正式锁定前进行必要的调整或启动仪式。


*/
contract ShibaMemeCoin is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // 说明：使用 SafeMath 可避免在算术运算时发生溢出（尽管从0.8.x开始Solidity自带检查）。

    // 基础参数配置
    // MAX_SUPPLY: 代币最大（初始）发行量（带18位小数，单位为最小代币单位）
    uint256 private constant MAX_SUPPLY = 1_000_000_000_000_000 * 10**18; // 1000万亿枚
    // INITIAL_SUPPLY: 初始铸造数量（此处等于MAX_SUPPLY，全部铸给部署者）
    uint256 private constant INITIAL_SUPPLY = MAX_SUPPLY;

    // 税费配置（以基点计，10000 = 100%）
    /*
        反射奖励是指，当网络上发生代币交易（买入、卖出或转账）时，合约会自动将部分交易税费按比例分配给所有现有的代币持有者。
        理论流程（反射机制的工作方式）：
        用户 A 卖出 SMEME，触发 8% 的卖出税。
        在 8% 的税费中，有 3% 的代币被标记为 reflectionFee。
        合约会通过复杂的数学计算（通常使用 r 余额/t 余额模型，您合约中定义的 _rOwned 和 _tOwned 变量就是为此服务的），在执行转账时，悄悄减少所有地址的原始余额映射，同时增加一个公共的“累积奖励乘数”。
        当您查看钱包余额时，合约会计算您的 r 余额（反射余额）对应的 t 余额（实际代币数量），这时您的余额会比上次查询时增加了反射奖励代币。

        所有的交易税费（买入税、卖出税、转账税）在被收取时，收取的都是 SMEME 代币，而不是 ETH。
        ETH 只在 后续的分配阶段 才会被引入。
        2、分配阶段：
            代币 \rightarrow ETH \rightarrow 流动性/营销合约地址积累了足够的 SMEME 代币（达到 swapThreshold）后，就会触发 _swapAndLiquify 流程，此时 ETH 才会进入流程：
            a、代币分配： 合约将积累的 SMEME 代币按照 liquidityFee、marketingFee、burnFee 的比例进行分割。
            b、销毁和预留： burnFee 部分被销毁；liquidityFee 的一半被预留（作为 SMEME 代币部分）。
            c、代币交换为 ETH： 剩余的 SMEME 代币（用于营销和流动性的 ETH 部分）被发送到 Uniswap Router，交换为 ETH。
            d、ETH 分配： 交换所得的 ETH 会被分成两部分：一部分用于和预留的 SMEME 代币一起添加到流动性池。另一部分发送给 marketingWallet
        
        所有的费用都是以 SMEME 代币的形式收取的。 
        但是，在最终的分配阶段：营销费用 的份额会被转换为 ETH，然后发送给 marketingWallet。
        其他费用（流动性、销毁、反射）则以 SMEME 代币（或 ETH 对应的流动性份额）的形式导向其目的地。

        费用名称,   征收时的形态 (Phase I), 最终分配时的形态 (Phase II)
        营销费用,   SMEME 代币,             ETH (发送给 marketingWallet)
        流动性费用, SMEME 代币,             SMEME 代币 (一半) + ETH (一半) → LP Token
        销毁费用,   SMEME 代币,             SMEME 代币 (发送给 deadAddress)
        反射费用,   SMEME 代币,             SMEME 代币 (留在流通中，通过 r/t 机制分配)

        LP Token 绝对不是指 ETH。
        LP Token (Liquidity Provider Token) 是一种单独的 ERC-20 代币，代表您在流动性池中所占的份额。它是在您将 SMEME 代币和 ETH 投入池子后，由 Uniswap V2 Pair 合约铸造给您的凭证。
            1、投入资产： 在 _addLiquidity 函数中，合约将 SMEME 代币和 ETH 同时发送给 Uniswap Router。
            2、铸造 LP Token： Uniswap Router 接收 SMEME 和 ETH，将它们放入流动性池中。作为回报，Uniswap Router 会铸造一个新的 LP Token，然后将这个 LP Token 发送到 liquidityWallet。
            3、结果： liquidityWallet 最终持有的资产是：LP Token。这个 Token 代表它对 SMEME/ETH 流动性池的拥有权。
        LP Token 就像一个收据或证书，它代表着您在 SMEME/ETH 池子里所拥有的资产（ETH 和 SMEME）的份额。它本身不是 ETH


       两种截然不同的费率结构：
        静态/传统税费： 流动性费、营销费、销毁费。
        动态/反射奖励费： reflectionFee。     

    如果使用了反射费： 总的扣费比例 Total Taker Fee 会包含 reflectionFee
    Total Taker Fee = Liquidity Fee + Marketing Fee + Burn Fee + Reflection Fee


    */
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

    // 交易限制配置（用于防刷、限制单笔交易量/最大持仓/交易频率等）
    struct TradingLimits {
        uint256 maxTransactionAmount;    // 最大交易量
        uint256 maxWalletAmount;         // 最大持有量
        uint256 minTimeBetweenTx;        // 交易间隔时间
        bool limitsInEffect;             // 限制是否生效
    }

    TradingLimits public tradingLimits;

    // 地址配置
    // marketingWallet: 接收营销费用的地址
    // liquidityWallet: 添加流动性时接收LP或代币的地址（这里作为流动性接收者）
    // deadAddress: 销毁代币的地址（通常使用烧毁地址）
    address public marketingWallet;
    address public liquidityWallet;

    /*
    一个非常著名且约定俗成的销毁地址，在整个以太坊和 EVM 兼容的区块链生态系统中，它被广泛用作“黑洞”地址
    这个地址之所以成为通用的销毁地址，是因为它的设计目的是确保发送到该地址的代币永远无法被取出或使用，同时它又具有一个易于识别的后缀——dEaD
    1. 密钥无法生成 (Unspendable Private Key)
        代币的转移需要一个私钥来签署交易。
        0x0000... 开头的地址通常被称为“零地址”或“空地址”。
        这个地址，以及其他许多由一系列零和特殊字符组成的地址，是无法通过正常的密码学过程生成对应私钥的。
        结果： 由于没有人拥有控制这个地址所需的私钥，任何发送到这个地址的代币都将永远被锁定，实现了永久销毁的目的。
    2.易于识别和审计 (The "dEaD" Suffix)
        销毁地址的目的是向社区证明代币已被移除流通。
        0x0000...dEaD 的后缀是区块链社区为了方便识别和记忆而约定的。
        结果： 当用户或审计员看到代币被发送到这个地址时，他们能立即理解这是用于销毁目的，提高了合约的透明度和可信度    
    3.避免与其他地址冲突 (Safety and Standardization)
        在早期的代币合约中，有些合约会使用 0x0000...0000 作为销毁地址。然而，这个地址在 EVM 中具有特殊的含义（例如，作为创建合约的默认发送方）。   
    */
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    // Uniswap 配置：路由合约地址和为本代币创建的交易对地址
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    // 状态变量
    // tradingEnabled: 是否对所有用户开放交易（部署后可由 owner 打开）
    bool public tradingEnabled = false;

    // swapEnabled: 是否允许合约在交易中触发 swap & liquify
    bool public swapEnabled = false;

    // inSwap: 互斥标志，防止重入或递归触发 swap
    bool private inSwap = false;

    // swapThreshold: 合约代币余额达到该阈值时触发 swap/流动性操作
    uint256 public swapThreshold;

    // 映射（状态映射）
    // isExcludedFromFees: 标记哪些地址免收交易费（owner、合约自身等）
    mapping(address => bool) public isExcludedFromFees;

    // isExcludedFromLimits: 标记哪些地址不受交易限制（如大额地址、合约等）
    mapping(address => bool) public isExcludedFromLimits;

    // automatedMarketMakerPairs: 标记哪些地址是自动化做市商（AMM）对，判断买/卖
    mapping(address => bool) public automatedMarketMakerPairs;

    // lastTransactionTime: 记录地址上一次交易时间（用于节流）
    mapping(address => uint256) public lastTransactionTime;

    // isBlacklisted: 黑名单地址，禁止转入/转出
    mapping(address => bool) public isBlacklisted;

    // 反射（Reflection）机制变量（为了实现代币持有者分红/反射）
    // MAX/_rTotal/_tTotal 等用于双重计数系统（反射代币常见实现）：
    // - _tTotal 表示实际代币总量（token total）
    // - _rTotal 表示反射单位总量（reflection total），用于将手续费按比例分配
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = INITIAL_SUPPLY;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    
    // _rOwned/_tOwned: 记录地址的反射量和实际代币量（当地址被排除反射时使用）
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => bool) private _isExcludedFromReward;
    address[] private _excludedFromReward;

    // 事件定义（用于链上监听状态变更）
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

    // modifier lockTheSwap: 在执行 swapAndLiquify 时设置互斥标志，防止重入。

    constructor(
        address _marketingWallet,
        address _liquidityWallet,
        address _router
    ) ERC20("ShibaMemeCoin", "SMEME") {
        // 初始化钱包地址（部署时由部署者传入）
        marketingWallet = _marketingWallet;
        liquidityWallet = _liquidityWallet;

        // 初始化 Uniswap 路由与交易对（创建本代币/WETH 交易对）
        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());

        // 将主交易对标记为自动化做市商对（用于在转账中区分买/卖）
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

        // 初始化交易限制（可在部署后由 owner 调整）
        tradingLimits = TradingLimits({
            maxTransactionAmount: INITIAL_SUPPLY.mul(1).div(100),  // 1% 最大交易量
            maxWalletAmount: INITIAL_SUPPLY.mul(2).div(100),       // 2% 最大持有量
            minTimeBetweenTx: 30,                                  // 30秒交易间隔
            limitsInEffect: true
        });

        // 设置合约触发 swap 的阈值（当合约自身代币余额 >= swapThreshold 时会触发）
        // 这里设为初始供应的 0.05%
        swapThreshold = INITIAL_SUPPLY.mul(5).div(10000); // 0.05%

        // 将一些特殊地址设为免收手续费与不受限制（例如 owner、合约自身、营销/流动性地址、销毁地址）
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

        // 初始化反射分配：将全部反射单位分配给 owner（配合 _mint 一起工作）
        _rOwned[owner()] = _rTotal;

        // 铸造初始供应量给合约部署者
        _mint(owner(), INITIAL_SUPPLY);

        emit Transfer(address(0), owner(), INITIAL_SUPPLY);
    }

    // 接收 ETH：合约可以直接接收 ETH（例如 swap 后的余额）
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
    /*
    用初始税率示例： 假设合约有 100 个代币余额，且税费比例为：
        liquidityFee: 2%
        marketingFee: 4%
        burnFee: 1%
        总费用 (TotalFees): 7%

    在 _swapAndLiquify 中：
        销毁： 约 14.3 个代币 (100 * 1/7) 被销毁。
        流动性（LP）： 约 7.15 个代币 (100 * 2/7 / 2) 被预留作为代币的一半。
        交换成 ETH： 剩下的代币（约 78.55 个）被交换成 ETH，用于营销和流动性的 ETH 部分。
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

        // 如果交易未启用，仅允许被免手续费的地址（通常 owner/合约）进行转账
        if (!tradingEnabled) {
            require(isExcludedFromFees[from] || isExcludedFromFees[to], "Trading not enabled");
        }

        // 应用交易限制（如最大交易量、最大钱包持有以及时间间隔限制）
        if (tradingLimits.limitsInEffect) {
            _applyTradingLimits(from, to, amount);
        }

        // 在满足条件时，合约会将自身持有的代币按比例 swap 为 ETH 并添加流动性、发送营销费
        // 这个逻辑避免在 AMM 卖出时重复触发（仅在非 AMM 转账触发 swap）
        if (
            swapEnabled &&
            !inSwap &&
            !automatedMarketMakerPairs[from] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to] &&
            balanceOf(address(this)) >= swapThreshold // balanceOf(address(this)) 的钱不计算本次转账收取的费用。
        ) {
            _swapAndLiquify(swapThreshold);
        }

        // 计算并收取税费（除在 swap 时或免手续费地址）
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
            // 交易时间间隔限制：当 target 是 AMM（即发起者在 AMM 卖出）时，检查卖方的时间间隔
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
    /*
    
    核心目的之一 就是将一部分累积的 SMEME 代币转换（Swap）成 ETH，以用于后续的流动性添加和营销费用分配

        swapAndLiquify 函数是分配代币的逻辑核心。
        它会根据 taxRates 中设定的比例（liquidityFee、marketingFee 和 burnFee）来分割这笔 contractTokenBalance
     */
    function _swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // 计算各部分税的总
        uint256 totalFees = taxRates.liquidityFee.add(taxRates.marketingFee).add(taxRates.burnFee);
        if (totalFees == 0) return;

        //流动性
        uint256 liquidityTokens = contractTokenBalance.mul(taxRates.liquidityFee).div(totalFees).div(2);

        // 营销 -- 其实最终也是转为ETH了
        uint256 marketingTokens = contractTokenBalance.mul(taxRates.marketingFee).div(totalFees);

        // 销毁
        uint256 burnTokens = contractTokenBalance.mul(taxRates.burnFee).div(totalFees);

        // 交换代币 == 总-流动-销毁
        // 营销费用（marketingFee）的份额已经被包含在用于交换的 swapTokens。
        // 如果不减去 liquidityTokens，那么全部的 contractTokenBalance 都会被包含在 swapTokens 中
        // 会将全部代币卖出换成 ETH。合约就没有 SMEME 代币剩下，无法与 ETH 配对来添加流动性。
        // 减去 liquidityTokens 的行为，在编程上等同于说：“将 liquidityTokens 数量的 SMEME 代币从待交换队列中排除，作为配对的资产预留在合约地址中。”
        uint256 swapTokens = contractTokenBalance.sub(liquidityTokens).sub(burnTokens);

        // 销毁代币
        if (burnTokens > 0) {
            //实际销毁代币
            super._transfer(address(this), deadAddress, burnTokens);
        }

        // 交换代币为ETH
        /*
        在 Solidity 和以太坊虚拟机（EVM）中，原生代币（ETH）和 ERC-20 代币的存储和查询方式是完全不同的
        原生代币（ETH）的余额是存储在 EVM 状态 中的，可以直接通过地址查询：
        ERC-20 代币（例如 SMEME）的余额是存储在代币合约的 内部存储映射 中的，必须通过调用代币合约的 balanceOf() 函数来查询
        */
        uint256 initialETHBalance = address(this).balance;
        // 交换代币：从合约地址转账给 Uniswap Router
        _swapTokensForEth(swapTokens);
        uint256 newETHBalance = address(this).balance.sub(initialETHBalance);

        // 分配ETH
        uint256 ethForLiquidity = newETHBalance.mul(taxRates.liquidityFee).div(totalFees.sub(taxRates.burnFee)).div(2);
        uint256 ethForMarketing = newETHBalance.sub(ethForLiquidity);

        // 添加流动性：从合约地址转账给 Uniswap Router
        /*
            非常重要的逻辑
            1、在最终添加流动性时，必须严格按照流动性池（Pair 合约）的实时价格比例来配对。
            2、自动流动性机制中 $SMEME$ 代币和 $ETH$ 的数量是 先根据税率分配份额，然后 在最终添加流动性时， 使用 Uniswap Router 来保证满足 实际价格比例的。
            这个过程分为“内部计算”（根据税率）和“外部执行”（根据市场价格）。
            阶段一：内部计算（根据税率确定份额）$SMEME$ 合约首先根据自身设定的税率，确定需要为流动性（LP）准备多少 $SMEME$ 代币和多少 $ETH$ 的份额。
                   确定 $SMEME$ 代币份额：这是由 liquidityFee 决定的。这部分代币（$50\%$ 的 liquidityFee 对应的 $SMEME$）是预留在合约中的。
                   确定 $ETH$ 份额：这是由另一半 $50\%$ 的 liquidityFee 对应的 $SMEME$ 代币卖出后，转换成的 $ETH$ 决定的。
                   在这个阶段，合约只保证 $SMEME$ 和 $ETH$ 在税费百分比上是等比例的，但并不能保证它们在实时市场价值上是等值的。
            阶段二：外部执行（使用 Uniswap Router 保证价格）关键点： 
                _addLiquidity 函数的调用必须依赖 Uniswap Router 来保证价格匹配。
                当合约调用 uniswapV2Router.addLiquidityETH 时，它会传入它所能提供的 $SMEME$ 代币数量 (tokenAmount) 和它所能提供的 $ETH$ 数量 (ethAmount)。
                为了确保配对成功，Uniswap Router 提供了两个关键参数：
                    amountTokenMin：合约最低愿意投入的 $SMEME$ 代币数量。
                    amountETHMin：合约最低愿意投入的 $ETH$ 数量。
                在合约代码中，这两个参数都被设置为 0：    
                当 amountTokenMin 和 amountETHMin 都设置为 0 时，Uniswap Router 的逻辑是：
                1、它会以流动性池当前的实时价格为基准。
                2、它将使用所有传入的 $SMEME$ 代币 (tokenAmount)。
                3、然后，它会从传入的 $ETH$ 总量 (ethAmount) 中，只取走与 tokenAmount 价值完全等值的 $ETH$ 来进行配对。
                4、如果传入的 ethAmount 大于所需值，多余的 $ETH$ 会被退还给合约地址。
            实际价格说了算
            即使 $SMEME$ 合约内部计算的 $SMEME$ 和 $ETH$ 数量因为市场波动而价值不等，只要：
            1、合约有足够的 $ETH$（即 ethAmount 足够高）。
            2、amountTokenMin 和 amountETHMin 设置为 $0$。
            那么 Uniswap Router 就会：全部使用 $SMEME$ 代币，并只取等值的 $ETH$，从而保证配对比例严格符合流动性池的实际市场价格。

            因此，实际价格 才是最终决定配对比例的因素，而税率只是决定了输入给 Uniswap Router 的资产总量。

            合约地址中多余的 $ETH$ 是如何处理的？
            1. 盈余产生的原因 (ETH Overload)正如我们在上一个问题中讨论的，在 addLiquidityETH 调用中，合约通常会传入比实际需要量 更多 的 $ETH$。
                传入 $ETH$： 由 _swapTokensForEth 转换所得的 $ETH$ 总量 (ethAmount)。
                实际需要 $ETH$： 严格按照实时市场价格，与预留的 $SMEME$ 代币 (tokenAmount) 等值配对所需的 $ETH$ 数量。
                由于 ethAmount 是根据税率比例计算出来的，它通常会高于配对所需的 $ETH$，尤其是在 $SMEME$ 代币价格下跌时。
                Uniswap Router 的行为：在 addLiquidityETH 中，Uniswap Router 只会取走所需的 $ETH$ 进行配对，然后将未使用的 $ETH$ 退还给交易发起者，即 合约地址 (address(this))。
            2. $ETH$ 盈余的去向这笔退还给合约地址的多余 $ETH$ 的最终处理，取决于合约代码的后续逻辑：
                A. 归入营销钱包 (最可能的结果)
                    在绝大多数情况下，您看到的多余 $ETH$ 会被打包到营销费用中，转给项目方控制的营销钱包
                B. 留在合约地址 (零头或设计缺陷)
                本合约就留在了合约中，可以调用emergencyWithdrawETH提取。
        */
        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            _addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(liquidityTokens, ethForLiquidity, liquidityTokens);
        }

        // 发送营销费用
        if (ethForMarketing > 0) {
            // 将营销费用发送给营销钱包
            payable(marketingWallet).transfer(ethForMarketing);
        }
    }

    /**
     * @dev 交换代币为ETH
     */
    /*
        业务步骤：谁在调用？ 
        1、ShibaMemeCoin 合约调用它自己，将累积的税费代币 (swapTokens) 卖出。
        2、发生什么？ swapTokens 数量的 SMEME 代币从合约地址转给 Uniswap Router。
        3、税费收取： SMEME 合约会收取转账税（因为这是合约地址到 Router 的转账，而不是标准的买入/卖出，但通常也需要交费）。
        4、交换执行： Uniswap Router 基于实际收到的 SMEME 代币，从流动性池中取出相应的 ETH。
        5、ETH 接收： ETH 被发送回 SMEME 合约地址 (address(this))。
        6、后续： SMEME 合约现在有了 ETH，可以继续执行 _swapAndLiquify 的后续步骤：分配 ETH 到营销钱包和添加到流动性池。
    */
    function _swapTokensForEth(uint256 tokenAmount) private {
        // [SMEME 地址, WETH 地址]
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // $ShibaMemeCoin$ 合约通过在交易路径中指定 $WETH$ 地址，来确保其与路由器的 $ETH$ 功能顺利集成
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

        // 这行代码在内部触发了 super._transfer(address(this), address(uniswapV2Router), tokenAmount)
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