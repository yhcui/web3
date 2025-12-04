// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Treasury handler interface
 * @dev Any class that implements this interface can be used for protocol-specific operations pertaining to the treasury.
 * 金库就是一个由智能合约控制的钱包地址，用于存储和管理协议的资产（通常是治理代币、税收、费用或抵押资产）
 * 资金来源: 1、税收/费用: 在代币交易中收取的交易税。2、抵押物/储备: 协议运营中产生的收益或其他资产
 * 主要目的：协议资金管理: 集中存储资金，用于维护、发展和支持协议生态系统
 * 核心管理：权力通常掌握在 DAO（去中心化自治组织） 或 多签钱包（Multi-sig Wallet） 手中
 * treasuryHandler 合约本身会被设计成一个复杂的合约，它不允许任何人直接提取资金，而是只响应通过 DAO 投票通过的提案（例如，支付开发团队费用、提供流动性、营销支出等）。这确保了资金的使用是去中心化和透明的
 */
interface ITreasuryHandler {
    /**
     * @notice Perform operations before a transfer is executed.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     */
    // 转账前检查: 用于执行例如反机器人、交易冷却期检查、转账限额等强制性规则。
    function beforeTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external;

    /**
     * @notice Perform operations after a transfer is executed.
     * @param benefactor Address of the benefactor.
     * @param beneficiary Address of the beneficiary.
     * @param amount Number of tokens in the transfer.
     */
    // 转账后处理: 用于记录数据、更新状态或执行其他非强制性操作
    function afterTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external;
}