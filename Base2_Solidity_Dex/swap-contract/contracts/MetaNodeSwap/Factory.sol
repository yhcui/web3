// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "./interfaces/IFactory.sol";
import "./Pool.sol";

contract Factory is IFactory {
    mapping(address => mapping(address => address[])) public pools;

    Parameters public override parameters;

    function sortToken(
        address tokenA,
        address tokenB
    ) private pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint32 index
    ) external view override returns (address) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "ZERO_ADDRESS");

        // Declare token0 and token1
        address token0;
        address token1;

        (token0, token1) = sortToken(tokenA, tokenB);

        return pools[token0][token1][index];
    }

    function createPool(
        address tokenA,
        address tokenB,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external override returns (address pool) {
        // validate token's individuality
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");

        // Declare token0 and token1
        address token0;
        address token1;

        // sort token, avoid the mistake of the order
        (token0, token1) = sortToken(tokenA, tokenB);

        // get current all pools
        address[] memory existingPools = pools[token0][token1];

        /**
         为什么要判断相等，token0和token1相等 不就决定 了一个池子了么？
         它指出了 CLMM（集中流动性做市商）协议与传统 AMM 协议（如 Uniswap V2）之间的核心区别。
         在 Uniswap V2 或相似的传统 AMM 中，一个代币对 TokenA /TokenB 只能对应一个流动性池，因为它们都使用相同的恒定乘积公式 x * y = k，且费率通常固定（如 0.3%）。
         但在 CLMM 模型中，一个 Token对可以有多个 Pool。原因如下：
         1. 费率（fee）是多样的$\text{CLMM}$ 协议（如 Uniswap V3）允许为同一个代币对提供不同费率的流动性池。
         2. Tick边界（tickLower 和 tickUpper）是 Pool 的配置
         */
        // check if the pool already exists
        for (uint256 i = 0; i < existingPools.length; i++) {
            IPool currentPool = IPool(existingPools[i]);

            if (
                currentPool.tickLower() == tickLower &&
                currentPool.tickUpper() == tickUpper &&
                currentPool.fee() == fee
            ) {
                return existingPools[i];
            }
        }

        // save pool info
        // 1. 在创建 Pool 前，Factory 临时设置参数
        // 在 Factory.createPool 代码中，你只看到它设置了 parameters，然后创建了 Pool，最后删除了 parameters
        // Pool 合约之所以能获取配置，是因为它的constructor（构造函数）中硬编码了逻辑，来获取parameters，知道去哪里读取这些信息
        parameters = Parameters(
            address(this),
            token0,
            token1,
            tickLower,
            tickUpper,
            fee
        );

        // generate create2 salt
        // salt 在这里的作用与配置参数的传递无关，它仅仅用于确定性地计算新 Pool 合约的地址
        bytes32 salt = keccak256(
            abi.encode(token0, token1, tickLower, tickUpper, fee)
        );

        /* 
            pool = address(new Pool{salt: salt}()); 这行代码确实没有直接传入 tickLower, tickUpper, 或 fee 等参数给 Pool 合约的构造函数。
            这是因为在您提供的 CLMM 模型中，这些 Pool 的核心配置参数不是通过传统的构造函数参数传递的，而是通过 Factory 合约的全局状态变量和 create2 地址的确定性来传递和初始化的
            为什么不用构造函数参数？
            在标准的 Uniswap V3 模型中，Pool 合约的构造函数（constructor）通常不接受参数。相反，它依赖于外部机制来获取其配置。
        */
        //2. 然后使用 create2 创建 Pool
        // create2 机制： 以太坊的 CREATE2 操作码允许根据 Factory 地址、salt 值 和 待部署合约的字节码，在部署之前就确定合约的最终地址。
        // create pool
        pool = address(new Pool{salt: salt}());

        // save created pool
        pools[token0][token1].push(pool);

        // delete pool info
        delete parameters;

        emit PoolCreated(
            token0,
            token1,
            uint32(existingPools.length),
            tickLower,
            tickUpper,
            fee,
            pool
        );
    }
}
