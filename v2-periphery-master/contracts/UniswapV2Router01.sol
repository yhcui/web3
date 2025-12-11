// SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './libraries/UniswapV2Library.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router01 is IUniswapV2Router01 {
    // 工厂合约地址
    address public immutable override factory;
    // WETH合约地址
    address public immutable override WETH;

    // 时间限制修饰符，确保交易未过期
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // 构造函数，初始化工厂合约和WETH地址
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // 接收ETH转账，只允许来自WETH合约的转账
    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** 添加流动性 ****
    /**
     * @dev 计算添加流动性的最优数量
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param amountADesired 期望添加的代币A数量
     * @param amountBDesired 期望添加的代币B数量
     * @param amountAMin 代币A最小添加数量
     * @param amountBMin 代币B最小添加数量
     * @return amountA 实际添加的代币A数量
     * @return amountB 实际添加的代币B数量
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // 如果交易对不存在则创建
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取交易对的储备量
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        // 如果是首次添加流动性
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 计算最优的代币B数量
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 计算最优的代币A数量
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    /**
     * @dev 添加代币流动性
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param amountADesired 期望添加的代币A数量
     * @param amountBDesired 期望添加的代币B数量
     * @param amountAMin 代币A最小添加数量
     * @param amountBMin 代币B最小添加数量
     * @param to 流动性代币接收地址
     * @param deadline 交易截止时间
     * @return amountA 实际添加的代币A数量
     * @return amountB 实际添加的代币B数量
     * @return liquidity 获得的流动性代币数量
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
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 安全转移代币A到交易对合约
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        // 安全转移代币B到交易对合约
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // 铸造流动性代币
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    
    /**
     * @dev 添加ETH和代币的流动性
     * @param token 代币地址
     * @param amountTokenDesired 期望添加的代币数量
     * @param amountTokenMin 代币最小添加数量
     * @param amountETHMin ETH最小添加数量
     * @param to 流动性代币接收地址
     * @param deadline 交易截止时间
     * @return amountToken 实际添加的代币数量
     * @return amountETH 实际添加的ETH数量
     * @return liquidity 获得的流动性代币数量
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 转移代币到交易对合约
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // 将ETH存入WETH合约
        IWETH(WETH).deposit{value: amountETH}();
        // 转移WETH到交易对合约
        assert(IWETH(WETH).transfer(pair, amountETH));
        // 铸造流动性代币
        liquidity = IUniswapV2Pair(pair).mint(to);
        // 如果有多余的ETH则退还给用户
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    // **** 移除流动性 ****
    /**
     * @dev 移除代币流动性
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param liquidity 要移除的流动性代币数量
     * @param amountAMin 代币A最小接收数量
     * @param amountBMin 代币B最小接收数量
     * @param to 代币接收地址
     * @param deadline 交易截止时间
     * @return amountA 实际获得的代币A数量
     * @return amountB 实际获得的代币B数量
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将流动性代币转移到交易对合约
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        // 销毁流动性并获得代币
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    
    /**
     * @dev 移除ETH和代币的流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性代币数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH最小接收数量
     * @param to 代币接收地址
     * @param deadline 交易截止时间
     * @return amountToken 实际获得的代币数量
     * @return amountETH 实际获得的ETH数量
     */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 转移代币给用户
        TransferHelper.safeTransfer(token, to, amountToken);
        // 提取WETH为ETH
        IWETH(WETH).withdraw(amountETH);
        // 转移ETH给用户
        TransferHelper.safeTransferETH(to, amountETH);
    }
    
    /**
     * @dev 使用许可移除代币流动性
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param liquidity 要移除的流动性代币数量
     * @param amountAMin 代币A最小接收数量
     * @param amountBMin 代币B最小接收数量
     * @param to 代币接收地址
     * @param deadline 交易截止时间
     * @param approveMax 是否授权最大值
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountA 实际获得的代币A数量
     * @return amountB 实际获得的代币B数量
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
    ) external override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用许可签名授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    
    /**
     * @dev 使用许可移除ETH和代币的流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性代币数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH最小接收数量
     * @param to 代币接收地址
     * @param deadline 交易截止时间
     * @param approveMax 是否授权最大值
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountToken 实际获得的代币数量
     * @return amountETH 实际获得的ETH数量
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        // 使用许可签名授权
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** 兑换 ****
    /**
     * @dev 执行代币兑换的核心逻辑
     * @param amounts 各路径节点的代币数量数组
     * @param path 兑换路径数组
     * @param _to 最终接收地址
     */
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            // 如果不是最后一步，中间交易对地址为下一个交易对，否则为最终接收地址
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            // 执行兑换
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    
    /**
     * @dev 用精确数量的代币兑换尽可能多的另一种代币
     * @param amountIn 输入代币数量
     * @param amountOutMin 最小输出代币数量
     * @param path 兑换路径数组
     * @param to 输出代币接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 转移输入代币到第一个交易对
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    
    /**
     * @dev 用尽可能少的代币兑换精确数量的另一种代币
     * @param amountOut 输出代币数量
     * @param amountInMax 最大输入代币数量
     * @param path 兑换路径数组
     * @param to 输出代币接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 转移输入代币到第一个交易对
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    
    /**
     * @dev 用精确数量的ETH兑换尽可能多的代币
     * @param amountOutMin 最小输出代币数量
     * @param path 兑换路径数组（必须以WETH开头）
     * @param to 输出代币接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将ETH存入WETH并转移给第一个交易对
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    
    /**
     * @dev 用尽可能少的代币兑换精确数量的ETH
     * @param amountOut 输出ETH数量
     * @param amountInMax 最大输入代币数量
     * @param path 兑换路径数组（必须以WETH结尾）
     * @param to ETH接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 转移输入代币到第一个交易对
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        // 提取WETH为ETH并转移给用户
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    /**
     * @dev 用精确数量的代币兑换尽可能多的ETH
     * @param amountIn 输入代币数量
     * @param amountOutMin 最小输出ETH数量
     * @param path 兑换路径数组（必须以WETH结尾）
     * @param to ETH接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 转移输入代币到第一个交易对
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        // 提取WETH为ETH并转移给用户
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    /**
     * @dev 用尽可能少的ETH兑换精确数量的代币
     * @param amountOut 输出代币数量
     * @param path 兑换路径数组（必须以WETH开头）
     * @param to 输出代币接收地址
     * @param deadline 交易截止时间
     * @return amounts 各路径节点的代币数量数组
     */
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将ETH存入WETH并转移给第一个交易对
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // 如果有多余的ETH则退还给用户
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    // **** 报价和计算函数 ****
    /**
     * @dev 计算给定输入金额的输出金额（固定乘积公式）
     * @param amountA 输入代币数量
     * @param reserveA 输入代币储备量
     * @param reserveB 输出代币储备量
     * @return amountB 输出代币数量
     */
    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    /**
     * @dev 计算给定输入金额的输出金额（考虑手续费）
     * @param amountIn 输入代币数量
     * @param reserveIn 输入代币储备量
     * @param reserveOut 输出代币储备量
     * @return amountOut 输出代币数量
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @dev 计算给定输出金额所需的输入金额（考虑手续费）
     * @param amountOut 输出代币数量
     * @param reserveIn 输入代币储备量
     * @param reserveOut 输出代币储备量
     * @return amountIn 输入代币数量
     */
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut); // 注意：这里应该是getAmountIn
    }

    /**
     * @dev 计算多个交易对路径下的输出金额
     * @param amountIn 输入代币数量
     * @param path 兑换路径数组
     * @return amounts 各路径节点的代币数量数组
     */
    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    /**
     * @dev 计算多个交易对路径下所需的输入金额
     * @param amountOut 输出代币数量
     * @param path 兑换路径数组
     * @return amounts 各路径节点的代币数量数组
     */
    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}