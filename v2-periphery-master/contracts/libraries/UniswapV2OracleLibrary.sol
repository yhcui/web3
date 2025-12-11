pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
// 一个用于计算平均价格预言机的辅助库
library UniswapV2OracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    // 辅助函数，返回当前区块时间戳（限制在 uint32 范围内，即 [0, 2**32 - 1]）
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    // 使用反事实计算产生累积价格，以节省gas并避免调用sync
    /*
    获取交易对的最新累积价格数据
    如果距离上次更新已有时间间隔，则通过反事实计算来估算当前的累积价格
    这种方法避免了调用 sync() 函数，从而节省 gas 成本
    使用储备量比率乘以时间间隔来计算价格变化量

    工作原理
    1、获取历史数据: 从 IUniswapV2Pair 合约中读取最新的累积价格和时间戳
    2、实时计算: 如果有时间差，根据交易对的储备量 (reserve0, reserve1) 和时间间隔来计算新的累积价格
    3、反事实计算: 不需要真正执行交易，而是基于现有储备量推算价格变化

    累积价格数据是指在一段时间内价格的积分值，也就是价格与时间的乘积累加。具体来说：
        price0Cumulative: token0 相对于 token1 的累积价格   
        price1Cumulative: token1 相对于 token0 的累积价格

    Token0 相对于 Token1 的累积价格含义
        它记录了 1个单位的 token0 能够兑换多少个 token1 的历史累积值
        这个值随着时间推移不断累加，反映了价格在时间维度上的积分
    
    示例说明
        假设 ETH/USDT 交易对：
        token0 = ETH
        token1 = USDT
        price0Cumulative 就表示 ETH 相对于 USDT 的历史价格累积值
        数值含义：每单位 ETH 能兑换多少 USDT 的时间积分   

    反事实是一种基于当前状态推算未来状态的方法，而不需要实际执行操作或等待事件发生
    
    */
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
         // 获取交易对最新的累积价格
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            // 反事实计算: price1 的累积增量 = reserve0/reserve1 * 时间间隔
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}
