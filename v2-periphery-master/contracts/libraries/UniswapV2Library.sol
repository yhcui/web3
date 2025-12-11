pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

/**
 * @title UniswapV2Library
 * @notice Uniswap V2 核心工具库，提供各种计算和辅助函数
 * @dev 包含交易对地址计算、储备量获取、价格计算等功能
 */
library UniswapV2Library {
    using SafeMath for uint;

    /**
     * @notice 对两个代币地址进行排序
     * @dev 用于处理按照此顺序排序的交易对返回值
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @return token0 排序后的第一个代币地址
     * @return token1 排序后的第二个代币地址
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    /**
     * @notice 计算交易对的 CREATE2 地址，无需进行外部调用
     * @param factory 工厂合约地址
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @return pair 交易对合约地址
     */
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        // 这段代码实现了使用 CREATE2 算法计算 Uniswap V2 交易对合约地址的功能
        /*
         1、CREATE2 地址计算公式
           这是 Ethereum 的 CREATE2 操作码使用的地址计算公式
           公式为: keccak256(0xff ++ senderAddress ++ salt ++ bytecodeHash)
         2、各组成部分说明
            hex'ff': CREATE2 前缀标识符，固定值 0xff
            factory: 工厂合约地址，即部署交易对的工厂合约地址
            keccak256(abi.encodePacked(token0, token1)): Salt 值
                使用两个已排序的代币地址作为盐值
                确保相同代币对总是产生相同的交易对地址
            hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f': 初始化代码哈希
                这是 Uniswap V2 交易对合约的 creationCode 哈希值
                固定值，代表交易对合约的字节码哈希

         1. 计算 token0 和 token1 组合的哈希作为 salt
         2. 将所有组件按 CREATE2 规范组合: 0xff + factory + salt + initCodeHash
         3. 对组合数据进行 keccak256 哈希运算
         4. 取哈希结果的后 20 字节作为地址 --  在 Solidity 中，当将 uint256 转换为 address 时，会自动取最低的 20 字节（160位）作为地址值，这相当于取了哈希结果的"后 20 字节"。

         核心优势
            无需链上查询: 可以离线计算出交易对地址，节省 gas 成本
            确定性: 相同的代币对总是生成相同的地址
            安全性: 通过哈希确保地址唯一性和防碰撞
         这种方法使得 pairFor 函数能够高效地预测任意代币对的合约地址，而无需实际调用工厂合约。
         */
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    /**
     * @notice 获取并排序交易对的储备量
     * @param factory 工厂合约地址
     * @param tokenA 第一个代币地址
     * @param tokenB 第二个代币地址
     * @return reserveA tokenA 的储备量
     * @return reserveB tokenB 的储备量
     */
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        /*
            IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves() 。 这行代码就是用pairFor获取合约地址，然后转为IUniswapV2Pair在evm上调用。
            1、pairFor(factory, tokenA, tokenB) - 调用 pairFor 函数计算交易对合约地址
            2、IUniswapV2Pair(...) - 将计算出的地址转换为 IUniswapV2Pair 接口类型
            3、.getReserves() - 通过接口调用目标合约的 getReserves 方法
         */
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @notice 根据给定数量的资产和交易对储备量，返回另一资产的等价数量
     * @param amountA 给定的资产A数量
     * @param reserveA 资产A的储备数量
     * @param reserveB 资产B的储备数量
     * @return amountB 等价的资产B数量
     */
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    /**
     * @notice 给定输入资产数量和交易对储备量，返回另一资产的最大输出数量
     * @param amountIn 输入资产数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountOut 输出资产数量
     */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    /**
     * @notice 给定输出资产数量和交易对储备量，返回所需的输入资产数量
     * @param amountOut 输出资产数量
     * @param reserveIn 输入资产的储备数量
     * @param reserveOut 输出资产的储备数量
     * @return amountIn 输入资产数量
     */
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    /**
     * @notice 对任意数量的交易对执行链式的 getAmountOut 计算
     * @param factory 工厂合约地址
     * @param amountIn 初始输入数量
     * @param path 交易路径（代币地址数组）
     * @return amounts 每个跳转步骤的输出数量数组
     */
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @notice 对任意数量的交易对执行链式的 getAmountIn 计算
     * @param factory 工厂合约地址
     * @param amountOut 最终输出数量
     * @param path 交易路径（代币地址数组）
     * @return amounts 每个跳转步骤的输入数量数组
     */
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}