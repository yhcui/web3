pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

/**
 * @title UniswapV2Router02
 * @notice Uniswap V2 路由器实现，提供流动性管理、交易执行等功能
 * @dev 实现了 IUniswapV2Router02 接口，支持常规代币和转账时扣费代币的交易
 */
contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    // 工厂合约地址 - 不可变
    address public immutable override factory;
    // WETH 合约地址 - 不可变
    address public immutable override WETH;

    // 时间锁修饰符 - 确保交易在截止时间前执行
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    /**
     * @param _factory Uniswap V2 工厂合约地址
     * @param _WETH WETH 合约地址
     */
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    /**
     * @notice 接收 ETH 转账
     * @dev 只接受来自 WETH 合约的 ETH 转账
     */
    receive() external payable {
        assert(msg.sender == WETH);
    }

    // **** 添加流动性 ****
    
    /**
     * @notice 计算最优流动性数量
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param amountADesired 期望添加的 tokenA 数量
     * @param amountBDesired 期望添加的 tokenB 数量
     * @param amountAMin tokenA 最小添加数量
     * @param amountBMin tokenB 最小添加数量
     * @return amountA 实际使用的 tokenA 数量
     * @return amountB 实际使用的 tokenB 数量
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // 如果交易对不存在则创建
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        
        // 获取当前交易对的储备量
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        
        // 如果是首次添加流动性，则按期望比例添加
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 根据当前储备计算最优数量
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    /**
     * @notice 添加流动性到指定交易对
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param amountADesired 期望添加的 tokenA 数量
     * @param amountBDesired 期望添加的 tokenB 数量
     * @param amountAMin tokenA 最小添加数量
     * @param amountBMin tokenB 最小添加数量
     * @param to 流动性份额接收者地址
     * @param deadline 交易截止时间戳
     * @return amountA 实际使用的 tokenA 数量
     * @return amountB 实际使用的 tokenB 数量
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
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    
    /**
     * @notice 添加 ETH 流动性（ETH 将被包装成 WETH）
     * @param token 代币地址
     * @param amountTokenDesired 期望添加的代币数量
     * @param amountTokenMin 代币最小添加数量
     * @param amountETHMin ETH 最小添加数量
     * @param to 流动性份额接收者地址
     * @param deadline 交易截止时间戳
     * @return amountToken 实际使用的代币数量
     * @return amountETH 实际使用的 ETH 数量
     * @return liquidity 铸造的流动性份额数量
     */
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // 退还多余的 ETH
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** 移除流动性 ****
    
    /**
     * @notice 从指定交易对移除流动性
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountAMin tokenA 最小接收数量
     * @param amountBMin tokenB 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @return amountA 实际收到的 tokenA 数量
     * @return amountB 实际收到的 tokenB 数量
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // 发送流动性份额到交易对
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    
    /**
     * @notice 从 ETH 交易对移除流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @return amountToken 实际收到的代币数量
     * @return amountETH 实际收到的 ETH 数量
     */
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    
    /**
     * @notice 使用许可签名从交易对移除流动性
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountAMin tokenA 最小接收数量
     * @param amountBMin tokenB 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @param approveMax 是否使用最大授权额度
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountA 实际收到的 tokenA 数量
     * @return amountB 实际收到的 tokenB 数量
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
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    
    /**
     * @notice 使用许可签名从 ETH 交易对移除流动性
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @param approveMax 是否使用最大授权额度
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountToken 实际收到的代币数量
     * @return amountETH 实际收到的 ETH 数量
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** 移除流动性 (支持转账时扣费代币) ****
    
    /**
     * @notice 从 ETH 交易对移除流动性，支持转账时扣费代币
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @return amountETH 实际收到的 ETH 数量
     */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 使用实际余额而不是计算值来转移代币
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    
    /**
     * @notice 使用许可签名从 ETH 交易对移除流动性，支持转账时扣费代币
     * @param token 代币地址
     * @param liquidity 要移除的流动性份额数量
     * @param amountTokenMin 代币最小接收数量
     * @param amountETHMin ETH 最小接收数量
     * @param to 代币接收者地址
     * @param deadline 交易截止时间戳
     * @param approveMax 是否使用最大授权额度
     * @param v 签名参数v
     * @param r 签名参数r
     * @param s 签名参数s
     * @return amountETH 实际收到的 ETH 数量
     */
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** 交换 ****
    
    /**
     * @notice 执行链式兑换操作
     * @param amounts 每个跳转步骤的金额数组
     * @param path 兑换路径（代币地址数组）
     * @param _to 最终接收者地址
     */
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    
    /**
     * @notice 使用精确输入金额兑换代币
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    /**
     * @notice 使用最大输入金额兑换精确输出代币
     * @param amountOut 需要获得的输出代币数量
     * @param amountInMax 输入代币的最大数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    /**
     * @notice 使用精确数量的 ETH 兑换代币
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    
    /**
     * @notice 使用最大数量的代币兑换精确数量的 ETH
     * @param amountOut 需要获得的 ETH 数量
     * @param amountInMax 输入代币的最大数量
     * @param path 兑换路径（代币地址数组）
     * @param to ETH 的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    /**
     * @notice 使用精确数量的代币兑换 ETH
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出 ETH 的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to ETH 的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    
    /**
     * @notice 使用 ETH 兑换精确数量的代币
     * @param amountOut 需要获得的代币数量
     * @param path 兑换路径（代币地址数组）
     * @param to 代币的接收者地址
     * @param deadline 交易截止时间戳
     * @return amounts 每个跳转步骤的实际金额数组
     */
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // 退还多余的 ETH
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** 交换 (支持转账时扣费代币) ****
    
    /**
     * @notice 执行链式兑换操作，支持转账时扣费代币
     * @param path 兑换路径（代币地址数组）
     * @param _to 最终接收者地址
     */
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // 作用域限制以避免堆栈太深错误
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            // 通过检查交易对合约中的代币余额变化来计算实际输入数量
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    
    /**
     * @notice 使用精确输入金额兑换代币，支持转账时扣费代币
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收者地址
     * @param deadline 交易截止时间戳
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    
    /**
     * @notice 使用精确数量的 ETH 兑换代币，支持转账时扣费代币
     * @param amountOutMin 输出代币的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to 输出代币的接收者地址
     * @param deadline 交易截止时间戳
     */
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    
    /**
     * @notice 使用精确数量的代币兑换 ETH，支持转账时扣费代币
     * @param amountIn 输入代币的确切数量
     * @param amountOutMin 输出 ETH 的最小数量
     * @param path 兑换路径（代币地址数组）
     * @param to ETH 的接收者地址
     * @param deadline 交易截止时间戳
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** 库函数 ****
    
    /**
     * @notice 根据给定数量和储备计算等价数量
     * @param amountA 给定的资产A数量
     * @param reserveA 资产A的储备数量
     * @param reserveB 资产B的储备数量
     * @return amountB 等价的资产B数量
     */
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    /**
     * @notice 计算给定输入数量时的输出数量
     * @param amountIn 输入数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountOut 输出数量
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @notice 计算给定输出数量时需要的输入数量
     * @param amountOut 输出数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountIn 输入数量
     */
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /**
     * @notice 计算多跳兑换的输出数量序列
     * @param amountIn 输入数量
     * @param path 兑换路径
     * @return amounts 每个跳转步骤的输出数量
     */
    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    /**
     * @notice 计算多跳兑换的输入数量序列
     * @param amountOut 输出数量
     * @param path 兑换路径
     * @return amounts 每个跳转步骤的输入数量
     */
    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}