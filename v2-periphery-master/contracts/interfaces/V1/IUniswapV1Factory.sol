pragma solidity >=0.5.0;
/*
一、什么是交易所合约？
交易所合约（exchange contract）是 Uniswap V1 协议中的核心组件，它是一个智能合约，负责管理特定 ERC-20 代币与 ETH 之间的交易对。

交易所合约的主要特点：
1、一对一映射：每个 ERC-20 代币都有其唯一对应的交易所合约
2、交易功能：实现代币与 ETH 之间的兑换功能
3、流动性管理：支持添加和移除流动性

二、工厂合约的作用：
IUniswapV1Factory 接口定义的 getExchange(address) 函数用于：
    通过代币地址查询其对应的交易所合约地址
    充当注册表角色，维护代币与交易所的映射关系

三、交易所合约的功能示例：
根据 IUniswapV1Exchange 接口，典型的交易所合约会包含以下功能：
    tokenToEthSwapInput：将代币兑换成 ETH
    ethToTokenSwapInput：将 ETH 兑换成代币
    removeLiquidity：移除流动性并取回资金
这种设计使得用户可以通过工厂合约轻松找到任何支持代币的交易所合约，从而进行交易操作。

 */
interface IUniswapV1Factory {
    // 根据代币地址获取对应的交易所地址
    // 参数: 代币合约地址
    // 返回值: 对应的 Uniswap V1 交易所合约地址
    function getExchange(address) external view returns (address);
}