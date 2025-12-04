// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Tax handler interface
 * @dev Any class that implements this interface can be used for protocol-specific tax calculations.
 */
// 用于定义一个税费处理模块，允许主协议（例如一个代币合约或 DeFi 协议）将复杂的税收计算逻辑外包给一个独立的、可插拔的合约
interface ITaxHandler {
    /**
     * @notice Get number of tokens to pay as tax.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     * @return Number of tokens to pay as tax.
     */
    // 计算在一次代币转移中，应该从转移的总金额中扣除多少代币作为税费。
    function getTax(
        address benefactor, // (恩惠者/给予者): 转出代币的地址（通常是发送者）
        address beneficiary, // (受益者): 接收代币的地址（通常是接收者）。
        uint256 amount // 本次转移的总代币数量
    ) external view returns (uint256);
}