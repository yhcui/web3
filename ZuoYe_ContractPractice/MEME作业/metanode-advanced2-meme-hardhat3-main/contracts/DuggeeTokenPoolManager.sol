// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DuggeeTokenPool.sol";

/**
 * @title DuggeeTokenPoolManager - 流动性池管理器
 * @dev 这是一个工厂合约，用于创建和管理多个DuggeeToken流动性池
 *
 * 主要功能：
 * 1. 创建流动性池：为DuggeeToken与不同ERC20代币创建独立的流动性池
 * 2. 池子管理：记录所有已创建的流动性池地址
 * 3. 池子查询：允许用户查询特定代币对应的流动性池地址
 *
 * 设计模式：工厂模式
 * 每个配对代币对应一个独立的流动性池，便于管理和扩展
 *
 */
contract DuggeeTokenPoolManager is Ownable {

    // ========== 状态变量 ==========

    /**
     * @dev DuggeeToken合约地址
     * 所有流动性池都将基于这个DuggeeToken创建
     */
    address public duggeeTokenAddress;

    /**
     * @dev 代币地址到流动性池地址的映射
     * key: 配对代币合约地址, value: 对应的流动性池合约地址
     * 每种配对代币只能有一个对应的流动性池
     */
    mapping(address => address) public pools;

    // ========== 构造函数 ==========

    /**
     * @dev 构造函数，初始化流动性池管理器
     *
     * @param _duggeeTokenAddress DuggeeToken合约地址
     */
    constructor(address _duggeeTokenAddress) Ownable(msg.sender) {
        duggeeTokenAddress = _duggeeTokenAddress;
    }

    // ========== 流动性池管理功能 ==========

    /**
     * @dev 创建新的流动性池（仅所有者）
     *
     * 功能：
     * 1. 检查该代币是否已有对应的流动性池
     * 2. 部署新的DuggeeTokenPool合约
     * 3. 记录新池子的地址到映射中
     *
     * @param tokenAddress 配对代币的合约地址
     */
    function createPool(address tokenAddress) external onlyOwner {
        // 检查该代币是否已有对应的流动性池
        require(pools[tokenAddress] == address(0), "Pool already exists");

        // 创建新的流动性池合约
        DuggeeTokenPool newPool = new DuggeeTokenPool(
            msg.sender,              // 池子所有者（调用此函数的管理员）
            duggeeTokenAddress,      // DuggeeToken地址
            tokenAddress            // 配对代币地址
        );

        // 记录新池子的地址
        pools[tokenAddress] = address(newPool);
    }

    /**
     * @dev 查询指定代币对应的流动性池地址
     *
     * @param tokenAddress 配对代币的合约地址
     * @return address 对应的流动性池合约地址，如果不存在则返回零地址
     */
    function getPool(address tokenAddress) external view returns (address) {
        return pools[tokenAddress];
    }
}
