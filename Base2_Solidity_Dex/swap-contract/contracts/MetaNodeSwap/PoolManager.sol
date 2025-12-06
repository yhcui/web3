// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "./interfaces/IPoolManager.sol";
import "./Factory.sol";
import "./interfaces/IPool.sol";

/*
CLMM（集中流动性做市商):。
sqrtPriceX96 代表的是流动性池子的当前价格，但它经过了特殊的数学编码，以适应 EVM（以太坊虚拟机）的浮点数运算限制。
sqrtPriceX96 是一个 编码后的数值，它表示了流动性池中 token0相对于 token1 的根号价格
sqrtPriceX96  = 开根号P * 2^96 。 P = token0/token1
通过乘以 2^96，开根号P 无论有多小，都能被提升为一个大整数 (uint160 类型)，从而在 EVM 中精确地进行计算。

sqrtPriceX96 的作用：
1. 决定交易的起点和终点当前价格： 它存储了流动性池的精确当前价格，是所有交易（swap）计算的起点。
    交易限制： sqrtPriceLimitX96 用来限制交易滑点或充当限价单的边界，确保交易不会以比用户预期的更差的价格成交。
2. 驱动价格变动在每次成功的 swap() 交易中，SwapMath.computeSwapStep 都会根据交易量计算出新的 sqrtPriceX96，并将其更新到 Pool 的状态变量中。
3. 指导流动性管理sqrtPriceX96 决定了当前 Tick 的位置，进而影响了哪些 LP 的流动性（liquidity）是活跃的（即在当前价格范围内）。
 当 sqrtPriceX96 跨越一个 Tick 边界时，Pool 的有效流动性 L 就会发生变化。

 为什么不直接用P？
 直接用P存储价格当然可以，但使用 sqrt P（根号价格）能极大地简化和优化核心的流动性计算。主要的理由有两个：简化积分计算 和 均匀精度。
  Uniswap V2 传统公式 x * y = k,
  CLMM 公式 X * Y= L^2
原因1简化核心积分计算：
求Token0 数量变化和求Token1 数量变化（公式无法写，可以从网上找一下。）
如果合约中存储的是 P 而不是 sqrt{P}：每次计算时，都需要重复执行昂贵的 sqrt() 操作。每次价格更新都需要计算 sqrt{P}。
原因2：
2. 均匀 Tick 精度（具体查资料，不方便在这里写注释）
如果使用 P 存储价格：价格 P 的变化是指数级的。当 i 变大时，两个相邻 Tick 的价格 P(i+1) - P(i) 的间距会变得非常大。在价格高的一端，一个 Tick 跨度代表的实际价格变化非常大，精度浪费严重。
 */
contract PoolManager is Factory, IPoolManager {
    // 此处只是token0和token1的交易对
    Pair[] public pairs;

    function getPairs() external view override returns (Pair[] memory) {
        return pairs;
    }

    function getAllPools()
        external
        view
        override
        returns (PoolInfo[] memory poolsInfo)
    {
        uint32 length = 0;
        // 先算一下大小
        for (uint32 i = 0; i < pairs.length; i++) {
            length += uint32(pools[pairs[i].token0][pairs[i].token1].length);
        }

        // 再填充数据
        poolsInfo = new PoolInfo[](length);
        uint256 index;
        for (uint32 i = 0; i < pairs.length; i++) {
            address[] memory addresses = pools[pairs[i].token0][
                pairs[i].token1
            ];
            for (uint32 j = 0; j < addresses.length; j++) {
                IPool pool = IPool(addresses[j]);
                poolsInfo[index] = PoolInfo({
                    pool: addresses[j],
                    token0: pool.token0(),
                    token1: pool.token1(),
                    index: j,
                    fee: pool.fee(),
                    feeProtocol: 0,
                    tickLower: pool.tickLower(),
                    tickUpper: pool.tickUpper(),
                    tick: pool.tick(),
                    sqrtPriceX96: pool.sqrtPriceX96(),
                    liquidity: pool.liquidity()
                });
                index++;
            }
        }
        return poolsInfo;
    }

    function createAndInitializePoolIfNecessary(
        CreateAndInitializeParams calldata params
    ) external payable override returns (address poolAddress) {
        require(
            params.token0 < params.token1,
            "token0 must be less than token1"
        );

        poolAddress = this.createPool(
            params.token0,
            params.token1,
            params.tickLower,
            params.tickUpper,
            params.fee
        );

        IPool pool = IPool(poolAddress);

        uint256 index = pools[pool.token0()][pool.token1()].length;

        // 新创建的池子，没有初始化价格，需要初始化价格
        // P（价格）在CLMM 中表示购买 1 个 Token0 需要花费多少 Token1。sqrtPriceX96 是这个价格 P 的根号和编码版本
        if (pool.sqrtPriceX96() == 0) {
            pool.initialize(params.sqrtPriceX96);

            if (index == 1) {
                // 如果是第一次添加该交易对，需要记录
                pairs.push(
                    Pair({token0: pool.token0(), token1: pool.token1()})
                );
            }
        }
    }
}
