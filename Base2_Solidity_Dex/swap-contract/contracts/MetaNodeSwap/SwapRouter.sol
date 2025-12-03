// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ISwapRouter.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolManager.sol";

contract SwapRouter is ISwapRouter {
    IPoolManager public poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(
        bytes memory reason
    ) private pure returns (int256, int256) {
        if (reason.length != 64) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (int256, int256));
    }
    /**
     * Swap (交换) 是指将一种代币兑换成另一种代币的操作。
     * 安全地调用底层流动性池（Pool）的 swap 方法，并处理其结果或错误
     * @param pool 
     * @param recipient 
     * @param zeroForOne 
     * @param amountSpecified 
     * @param sqrtPriceLimitX96 
     * @param data 
     */
    function swapInPool(
        IPool pool, // 目标 Pool 合约的实例接口
        address recipient, // 接收输出代币的地址。
        bool zeroForOne, // 交易方向 (true 用 Token0 换 Token1，false 反之)
        int256 amountSpecified, // 交易数量（正数代表输入量，负数代表输出量）。
        uint160 sqrtPriceLimitX96, // 价格限制（用于滑点控制或限价单）
        bytes calldata data // 编码给 swapCallback 的回调数据（包含支付方等信息）
    ) external returns (int256 amount0, int256 amount1) {
        // 交易结束后 Token0和 Token1的净变化量（遵循正流入/负流出约定）。
        try
            pool.swap(
                recipient,
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96,
                data
            )
        returns (int256 _amount0, int256 _amount1) {
            return (_amount0, _amount1);
        } catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }
    /**
     * 进行实际的提币操作
     * 这个函数用于执行一种标准的代币交换操作：用户指定精确的输入代币数量，合约计算并返回实际可以获得的输出代币数量。
     * 用户指定要投入的 amountIn，Router 负责将这笔资金按 indexPath 确定的路径，分配到各个流动性池进行交换，并返回最终获得的 amountOut
     * @param params 
     */
    function exactInput(
        ExactInputParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // 记录确定的输入 token 的 amount
        // 记录用户原始的输入数量。在多跳交易中，这个变量会不断更新，表示剩余待交换的输入量。
        uint256 amountIn = params.amountIn;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        // 如果 tokenIn 是 token0，则 zeroForOne 为 true
        //  如果 tokenIn 是 token1，则 zeroForOne 为 false
        // 这是 Uniswap V3 的惯例。根据代币地址的大小关系 (params.tokenIn < params.tokenOut) 确定本次交易的方向。
        // zeroForOne = true: 用户用 token0 换 token1, (tokenIn=token0, tokenOut=token1)
        // zeroForOne = false: 用户用 token1 换 token0, (tokenIn=token1, tokenOut=token0)
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );

            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swapCallback 函数需要的参数
            // data 会在 Pool 调用 Router 的 swapCallback 时被解码，告诉 Router 应该从哪里拉取代币
            bytes memory data = abi.encode(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i],
                params.recipient == address(0) ? address(0) : msg.sender
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            // 这个池子可以拿amount0换amount1个。更精确的说法是正的 amount：表示该代币数量流入池子。负的 amount：表示该代币数量流出池子
            (int256 amount0, int256 amount1) = this.swapInPool(
                pool,
                params.recipient, // 接收输出代币的地址。
                zeroForOne,
                int256(amountIn), // 交易数量（正数代表输入量，负数代表输出量）。
                params.sqrtPriceLimitX96, // 价格限制（用于滑点控制或限价单） sqrtPriceLimitX96 是一个由用户意愿（价格限制或滑点要求）驱动，但在链下经过数学转换后，最终传入智能合约的核心安全参数
                data
            );
            // amount0 和 amount1 的值来自 Pool，表示 Pool 在这次 swap 中实际吃掉的代币数量
            // 更新 amountIn 和 amountOut
            // 在 pool.swap() 中，返回值 (amount0, amount1) 有着严格的符号约定.正数（> 0）： 表示该代币流入 Pool 合约（Pool 收到）。负数（< 0）： 表示该代币流出 Pool 合约（Pool 支出）。
            amountIn -= uint256(zeroForOne ? amount0 : amount1);
            amountOut += uint256(zeroForOne ? -amount1 : -amount0);

            // 如果 amountIn 为 0，表示交换完成，跳出循环
            if (amountIn == 0) {
                break;
            }
        }

        // 滑点检查： 检查最终累积的 amountOut 是否满足用户设定的最低要求（amountOutMinimum）。这是 “确定输入量交易” 中的关键安全保护。
        // 如果交换到的 amountOut 小于指定的最少数量 amountOutMinimum，则抛出错误
        require(amountOut >= params.amountOutMinimum, "Slippage exceeded");

        // 发送 Swap 事件
        emit Swap(msg.sender, zeroForOne, params.amountIn, amountIn, amountOut);

        // 返回 amountOut
        return amountOut;
    }
    /**
     * @param params 
     */
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override returns (uint256 amountIn) {
        // 记录确定的输出 token 的 amount
        uint256 amountOut = params.amountOut;

        // 根据 tokenIn 和 tokenOut 的大小关系，确定是从 token0 到 token1 还是从 token1 到 token0
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // 遍历指定的每一个 pool
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPool(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i]
            );

            // 如果 pool 不存在，则抛出错误
            require(poolAddress != address(0), "Pool not found");

            // 获取 pool 实例
            IPool pool = IPool(poolAddress);

            // 构造 swapCallback 函数需要的参数
            
            bytes memory data = abi.encode(
                params.tokenIn,
                params.tokenOut,
                params.indexPath[i],
                params.recipient == address(0) ? address(0) : msg.sender
            );

            // 调用 pool 的 swap 函数，进行交换，并拿到返回的 token0 和 token1 的数量
            (int256 amount0, int256 amount1) = this.swapInPool(
                pool,
                params.recipient,
                zeroForOne,
                -int256(amountOut),
                params.sqrtPriceLimitX96,
                data
            );

            // 更新 amountOut 和 amountIn
            // 这是多跳交易的关键部分。在每一步交换完成后，Router 需要更新 amountIn 和 amountOut 的累积值
            amountOut -= uint256(zeroForOne ? -amount1 : -amount0);
            amountIn += uint256(zeroForOne ? amount0 : amount1);

            // 如果 amountOut 为 0，表示交换完成，跳出循环
            if (amountOut == 0) {
                break;
            }
        }

        // 如果交换到指定数量 tokenOut 消耗的 tokenIn 数量超过指定的最大值，报错
        require(amountIn <= params.amountInMaximum, "Slippage exceeded");

        // 发射 Swap 事件
        emit Swap(
            msg.sender,
            zeroForOne,
            params.amountOut,
            amountOut,
            amountIn
        );

        // 返回交换后的 amountIn
        return amountIn;
    }

    // 报价，指定 tokenIn 的数量和 tokenOut 的最小值，返回 tokenOut 的实际数量
    function quoteExactInput(
        QuoteExactInputParams calldata params
    ) external override returns (uint256 amountOut) {
        // 因为没有实际 approve，所以这里交易会报错，我们捕获错误信息，解析需要多少 token

        return
            this.exactInput(
                ExactInputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: address(0),
                    deadline: block.timestamp + 1 hours,
                    amountIn: params.amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    // 报价，指定 tokenOut 的数量和 tokenIn 的最大值，返回 tokenIn 的实际数量
    function quoteExactOutput(
        QuoteExactOutputParams calldata params
    ) external override returns (uint256 amountIn) {
        return
            this.exactOutput(
                ExactOutputParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    indexPath: params.indexPath,
                    recipient: address(0),
                    deadline: block.timestamp + 1 hours,
                    amountOut: params.amountOut,
                    amountInMaximum: type(uint256).max,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        // transfer token
        (address tokenIn, address tokenOut, uint32 index, address payer) = abi
            .decode(data, (address, address, uint32, address));
        address _pool = poolManager.getPool(tokenIn, tokenOut, index);

        // 检查 callback 的合约地址是否是 Pool
        require(_pool == msg.sender, "Invalid callback caller");

        uint256 amountToPay = amount0Delta > 0
            ? uint256(amount0Delta)
            : uint256(amount1Delta);
        // payer 是 address(0)，这是一个用于预估 token 的请求（quoteExactInput or quoteExactOutput）
        // 参考代码 https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/Quoter.sol#L38
        if (payer == address(0)) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amount0Delta)
                mstore(add(ptr, 0x20), amount1Delta)
                revert(ptr, 64)
            }
        }

        // 正常交易，转账给交易池
        if (amountToPay > 0) {
            IERC20(tokenIn).transferFrom(payer, _pool, amountToPay);
        }
    }
}
