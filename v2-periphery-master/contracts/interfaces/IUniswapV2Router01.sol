pragma solidity >=0.6.2;

/**
 * @title IUniswapV2Router01
 * @notice Uniswap V2 路由器接口版本1，定义了核心的流动性管理和交易功能
 * @dev 这是 Uniswap V2 路由器的基础接口，提供了添加/移除流动性和执行代币交换的基本方法
 */
interface IUniswapV2Router01 {
    /**
     * @notice 获取工厂合约地址
     * @return address 工厂合约地址
     */
    function factory() external pure returns (address);
    
    /**
     * @notice 获取WETH合约地址
     * @return address WETH合约地址
     */
    function WETH() external pure returns (address);

    /**
     * @notice 为两个代币添加流动性
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param amountADesired 期望添加的tokenA数量
     * @param amountBDesired 期望添加的tokenB数量
     * @param amountAMin tokenA的最小添加数量
     * @param amountBMin tokenB的最小添加数量
     * @param to 流动性份额接收者地址
     * @param deadline 交易截止时间戳
     * @return amountA 实际使用的tokenA数量
     * @return amountB 实际使用的tokenB数量
     * @return liquidity 铸造的流动性份额数量
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    
    /**
     * @notice 为代币和ETH添加流动性（ETH会被包装成WETH）
     * @param token 代币地址
     * @param amountTokenDesired 期望添加的代币数量
     * @param amountTokenMin 代币最小添加数量
     * @param amountETHMin ETH最小添加数量
     * @param to 流动性份额接收者地址
     * @param deadline 交易截止时间戳
     * @return amountToken 实际使用的代币数量
     * @return amountETH 实际使用的ETH数量
     * @return liquidity 铸造的流动性份额数量
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    /**
     * @notice 从两个代币的交易对中移除流动性
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountAMin tokenA最小接收数量
     * @param amountBMin tokenB最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @return amountA 实际收到的tokenA数量
     * @return amountB 实际收到的tokenB数量
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    
    /**
     * @notice 从代币-ETH交易对中移除流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @return amountToken 实际收到的代币数量
     * @return amountETH 实际收到的ETH数量
     */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    
    /**
     * @notice 使用许可签名从两个代币的交易对中移除流动性
     * @dev 结合permit功能，无需预先授权即可移除流动性
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountAMin tokenA最小接收数量
     * @param amountBMin tokenB最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @param approveMax 是否使用最大授权额度
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountA 实际收到的tokenA数量
     * @return amountB 实际收到的tokenB数量
     */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    
    /**
     * @notice 使用许可签名从代币-ETH交易对中移除流动性
     * @dev 结合permit功能，无需预先授权即可移除流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @param approveMax 是否使用最大授权额度
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountToken 实际收到的代币数量
     * @return amountETH 实际收到的ETH数量
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    
    /**
     * @notice 使用精确数量的代币兑换另一种代币
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    /**
     * @notice 使用最大数量的代币兑换精确数量的另一种代币
     * @param amountOut 需要获得的输出代币数量
     * @param amountInMax 输入代币的最大数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    /**
     * @notice 使用精确数量的ETH兑换代币
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    
    /**
     * @notice 使用最大数量的代币兑换精确数量的ETH
     * @param amountOut 需要获得的ETH数量
     * @param amountInMax 输入代币的最大数量
     * @param path 兑换路径（代币地址数组）
     * @param to ETH的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    
    /**
     * @notice 使用精确数量的代币兑换ETH
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出ETH的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to ETH的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    
    /**
     * @notice 使用ETH兑换精确数量的代币
     * @param amountOut 需要获得的代币数量
     * @param path 兑换路径（代币地址数组）
     * @param to 代币的接收地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    /**
     * @notice 根据给定数量和储备计算等价数量
     * @param amountA 给定的资产A数量
     * @param reserveA 资产A的储备数量
     * @param reserveB 资产B的储备数量
     * @return amountB 等价的资产B数量
     */
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    
    /**
     * @notice 计算给定输入数量时的输出数量
     * @param amountIn 输入数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountOut 输出数量
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    
    /**
     * @notice 计算给定输出数量时需要的输入数量
     * @param amountOut 输出数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountIn 输入数量
     */
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    
    /**
     * @notice 计算多跳兑换的输出数量序列
     * @param amountIn 输入数量
     * @param path 兑换路径
     * @return amounts 每个跳转步骤的输出数量
     */
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    /**
     * @notice 计算多跳兑换的输入数量序列
     * @param amountOut 输出数量
     * @param path 兑换路径
     * @return amounts 每个跳转步骤的输入数量
     */
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}