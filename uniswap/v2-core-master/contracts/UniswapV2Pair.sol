// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';
/*
主要功能说明：

1、流动性管理：

    mint() 添加流动性并铸造LP代币
    burn() 移除流动性并销毁LP代币
2、交易功能：

    swap() 实现代币交换功能
3、辅助功能：

    skim() 提取超出储备量的代币
    sync() 同步储备量与实际余额

4、安全机制：

    使用 lock 修饰符防止重入攻击
    _safeTransfer 确保代币转账的安全性
    多重校验确保恒定乘积公式不变性

5、价格预言机支持：
    通过 price0CumulativeLast 和 price1CumulativeLast 支持时间加权平均价格(TWAP)计算

工作流程
1、创建交易对: 通过工厂合约部署 UniswapV2Pair 实例

    对应方法: constructor()
    说明: 构造函数在部署合约时自动执行，设置 factory 地址为部署者地址

2、初始化: 设置交易对涉及的两种代币地址

    对应方法: initialize(address _token0, address _token1)
    说明: 由工厂合约调用一次，设置交易对的两种代币地址 (token0 和 token1)

3、提供流动性: 用户添加初始或追加流动性获得 LP 代币

    对应方法: mint(address to)
    说明: 用户调用此方法向交易对添加流动性，并获得代表其份额的 LP 代币

4、交易执行: 用户通过 swap 进行代币兑换

    对应方法: swap(uint amount0Out, uint amount1Out, address to, bytes calldata data)
    说明: 用户调用此方法进行两种代币之间的兑换交易

5、流动性提取: 用户燃烧 LP 代币取回本金及交易费收益

    对应方法: burn(address to)
    说明: 用户调用此方法移除流动性，燃烧 LP 代币并取回相应的代币资产

*/

// Uniswap V2 的核心交易对合约，实现了一个ERC-20代币对的自动做市商(AMM)逻辑
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    // 最小流动性，防止首次添加流动性时的初始流动性被提取完
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    // ERC20 transfer 函数的选择器签名
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint264)')));

    // 工厂合约地址
    address public factory;
    // 交易对中的第一个代币地址
    address public token0;
    // 交易对中的第二个代币地址
    address public token1;

    // 储备量状态变量，使用单个存储槽优化存储
    uint112 private reserve0;           // 使用单一存储槽，可通过 getReserves 访问
    uint112 private reserve1;           // 使用单一存储槽，可通过 getReserves 访问
    uint32  private blockTimestampLast; // 使用单一存储槽，可通过 getReserves 访问

    // 价格累积值，用于计算时间加权平均价格(TWAP)
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    // 上一次流动性事件后的 k 值 (reserve0 * reserve1)
    uint public kLast; 

    // 锁定机制，防止重入攻击
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // 获取储备量的公共视图函数
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // 安全转账函数，确保代币转账成功
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    // 铸造流动性事件
    event Mint(address indexed sender, uint amount0, uint amount1);
    // 销毁流动性事件
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    // 交换交易事件
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    // 同步储备量事件
    event Sync(uint112 reserve0, uint112 reserve1);

    // 构造函数，在部署时设置工厂地址为发送者
    constructor() public {
        factory = msg.sender;
    }

    // 初始化函数，由工厂合约在部署时调用一次
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // 足够的安全检查
        token0 = _token0;
        token1 = _token1;
    }

    // 更新储备量，并在每个区块的第一次调用时更新价格累积值
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        // 校验传入余额不会溢出（require(balance0 <= uint112(-1) ...)）。
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // 计算 timeElapsed 
        // timeElapsed 表示自上一次更新储备（blockTimestampLast）以来经过的秒数。合约用它把一段时间内的“即时价格”按时间加权累积到 priceCumulative，从而支持 TWAP（时间加权平均价）。
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // 溢出是预期行为
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * 永不溢出，+ 溢出是预期行为
            // 如果 timeElapsed > 0 且旧储备非 0，则使用旧储备值计算并累加 price0CumulativeLast 和 price1CumulativeLast（用于 TWAP 计算）。
            // 注意这里用的是旧的 _reserve0/_reserve1 来计算过去时间区间内的价格贡献。
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // 如果手续费开启，则铸造相当于 sqrt(k) 增长六分之一的流动性
    /*

    在 mint 函数中，没有"扣你的钱再还给你"的过程。正确的流程是：

        你先转账: 用户首先将代币转入 UniswapV2Pair 合约
        合约检测: 合约通过比较当前余额和储备量来确定新增的代币数量
        铸造LP代币: 根据你提供的流动性数量，为你铸造相应的LP代币
        更新储备: 更新储备量以反映新的流动性

    关于 _mintFee 函数，它是这样工作的：
        当有交易发生时，交易费会增加流动性池的规模
        协议会从这些增长中提取一部分作为费用
        这部分费用以新铸造的LP代币形式发放给协议金库
        这不是从你的流动性中扣除，而是从交易费积累中分配

    流动性与代币数量的关系
    在 UniswapV2Pair 中：

    1、流动性确实代表代币数量

    流动性池由两种代币组成：token0 和 token1
    每个池都有对应的储备量：reserve0 和 reserve1
    这些储备量就是实际存储在合约中的代币数量

    2、流动性提供者的权益

    当用户提供流动性时，他们会获得 LP 代币
    LP 代币的数量与提供的代币价值成正比
    用户可以通过燃烧 LP 代币来取回相应的代币份额

    3、交易费用的影响

    每笔交易都会向池中添加 0.3% 的费用
    这些费用以代币形式增加到 reserve0 和 reserve1 中
    因此池中实际代币数量会逐渐增加
    
    4、协议费用机制

    协议费用是从交易费用导致的增长中提取的
    不是直接从用户本金中扣除
    而是从池子因交易费而增长的部分中分配
    因此，流动性本质上就是池中持有的实际代币数量，而 LP 代币则是用户在池中所占份额的证明。    

    */
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        /*
        
        协议收入: 当 feeOn 为 true 时，协议可以从交易费中抽取一部分作为收入
        流动性激励: 收取的费用以 LP 代币形式发放给协议指定的地址
        治理控制: 通过工厂合约的 setFeeTo 方法可以开启或关闭此功能
        */
        address feeTo = IUniswapV2Factory(factory).feeTo();
        // 通过检查 feeTo 地址是否为非零地址来判断是否启用费用功能
        feeOn = feeTo != address(0);

        // 计算和铸造协议费用
        uint _kLast = kLast; // 节省gas -  将状态变量 kLast 加载到局部变量中，减少多次访问状态变量的Gas消耗。
        if (feeOn) {
            if (_kLast != 0) {
                // rootK: 当前储备量乘积的平方根 (√(reserve0 × reserve1))
                // rootKLast: 上次记录的 k 值的平方根 (√kLast)
                // 只有当 rootK > rootKLast 时才产生费用（即流动性增加）
                // 协议通过这部分增长收取费用 计算公式为： liquidity = (totalSupply × (rootK - rootKLast)) / (rootK × 5 + rootKLast)
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    // 这是 Uniswap V2 的协议费用计算公式：
                    // 分子: totalSupply × (rootK - rootKLast)
                    // 分母: rootK × 5 + rootKLast
                    // 结果: 费用以 LP 代币形式发放给 feeTo 地址
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;

                    // 只有当计算出的流动性大于0时，才会铸造 LP 代币给协议费用地址。
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // 这个低级函数应该从执行重要安全检查的合约中调用
    // 该方法允许用户向交易对中添加流动性，并获得代表其在池中份额的 LP 代币作为回报。
    // 接收新铸造 LP 代币的地址
    function mint(address to) external lock returns (uint liquidity) {
        // 获取当前交易对的储备量，用于计算新增的流动性数量。
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // 节省gas
        /*
        为什么这样计算？
        balance0 和 balance1: 获取当前合约地址持有的两种代币的实际余额
        _reserve0 和 _reserve1: 获取交易对记录的储备量（上一次操作后的正确储备值）
        amount0 和 amount1: 通过余额减去储备量，得到用户新添加的代币数量

        核心原理
        这是基于以下事实的设计：
        交易对合约的代币余额应该等于储备量
        当用户向合约转入代币但还未调用 mint 方法时，合约余额会大于储备量
        差额部分就是用户想要添加的流动性数量

        UniswapV2Pair 合约并不直接存储代币余额，而是通过以下方式管理代币：
        1. 通过ERC20代币合约查询余额
        solidity
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        这里的关键点是：

        address(this) 返回当前 UniswapV2Pair 合约的地址
        通过 IERC20(token0).balanceOf(address(this)) 查询该合约地址持有的 token0 代币数量
        通过 IERC20(token1).balanceOf(address(this)) 查询该合约地址持有的 token1 代币数量

        2. 两种代币的来源
        UniswapV2Pair 合约通过以下方式持有代币：

        用户通过 transfer 或 transferFrom 直接向合约地址发送代币
        在 swap 操作中，用户发送代币到合约
        在 mint 操作中，用户添加流动性时发送代币到合约
        差额部分：用户新增的流动性数量

        */
        // 通过比较当前合约余额与储备量，得出用户新增的两种代币数量。
        // 这段代码的逻辑是用来计算当前交易对合约中新增的代币数量
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        // 如果协议启用了费用功能，则计算并铸造相应费用给协议费用地址。
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // 节省gas，必须在此定义因为 totalSupply 可能在 _mintFee 中更新

        // 计算流动性数量 根据不同情况采用不同的计算方式
        if (_totalSupply == 0) {
            // 首次添加流动性
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // 永久锁定前 MINIMUM_LIQUIDITY 数量的代币
        } else {
            // 后续添加流动性
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 铸造 LP 代币.将计算出的流动性数量作为 LP 代币铸造给指定地址。
        _mint(to, liquidity);

        //更新交易对的储备量和相关状态。
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 和 reserve1 是最新的
        emit Mint(msg.sender, amount0, amount1);
    }

    // 这个低级函数应该从执行重要安全检查的合约中调用
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // 节省gas
        address _token0 = token0;                                // 节省gas
        address _token1 = token1;                                // 节省gas
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // 节省gas，必须在此定义因为 totalSupply 可能在 _mintFee 中更新
        amount0 = liquidity.mul(balance0) / _totalSupply; // 使用余额确保按比例分配
        amount1 = liquidity.mul(balance1) / _totalSupply; // 使用余额确保按比例分配
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 和 reserve1 是最新的
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // 这个低级函数应该从执行重要安全检查的合约中调用
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 至少有一种输出金额大于0
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // 节省gas
        // 输出金额不能超过当前储备量
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { 
            // 作用域限制 _token{0,1}，避免堆栈过深错误
            address _token0 = token0;
            address _token1 = token1;
            // 接收地址不能是交易对中的任一令牌
            require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
            // 乐观地转移代币
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); 
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); 
            // 如果有回调数据，则调用接收方的 uniswapV2Call 方法
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        // 计算实际输入金额
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        
        { 
            // 作用域限制 reserve{0,1}Adjusted，避免堆栈过深错误
            // 应用0.3%的交易费用后验证恒定乘积不变性
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // 强制使余额与储备量匹配
    function skim(address to) external lock {
        address _token0 = token0; // 节省gas
        address _token1 = token1; // 节省gas
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // 强制使储备量与余额匹配
    /*
    sync()：把实际余额写回储备并更新价格累积与时间戳。
    任何人可调用；内部有重入锁保护。
    不移动代币，仅修改会计数据；常用于修复余额/储备不一致或主动同步状态。
    调用会影响 TWAP 累积值，使用时注意可能与后续交易的组合效应。
    作用：把合约当前实际持有的两个代币余额（on-chain token balances）写入合约的“储备”状态（reserve0/reserve1），并在必要时更新价格累积值（TWAP 相关）和时间戳，从而使合约内部的会计记录与实际代币余额同步。
    场景：当有人直接向 Pair 合约转账代币（没有走 mint/transferFrom 等逻辑）或其他原因导致余额与记录的储备量不一致时，调用 sync() 可以强制让记录与真实余额一致。
    */
    function sync() external lock {
        /*
        IERC20(token0).balanceOf(address(this))：读取 token0 合约中当前 Pair 合约地址持有的 token0 实际余额（链上查询）。
        IERC20(token1).balanceOf(address(this))：同上，读取 token1 的实际余额。
        reserve0 / reserve1：当前合约内部记录的“储备量”（旧值），传入 _update 作为计算价格累积（TWAP）和时间差的参考值。
        */
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}