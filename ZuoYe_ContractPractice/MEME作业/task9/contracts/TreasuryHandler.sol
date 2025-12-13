// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITreasuryHandler} from "../interfaces/ITreasuryHandler.sol";

contract TreasuryHandler is ITreasuryHandler, Ownable {
    mapping(address => bool) public black_list;

    constructor(address owner) Ownable(owner) {}

    /**
     * @notice 交易执行前进行的操作
     *          检查黑名单
     *          检查交易冷却时间
     *          检查最大持有量限制
     *          触发自动卖出（将累积的税款换成ETH）
     * @param benefactor 交易发起方地址
     * @param beneficiary 交易接收方地址
     * @param amount 交易金额
     */
    function beforeTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view override onlyOwner {
        // 检查黑名单
        require(!black_list[benefactor], "Benefactor is in black list");
        require(!black_list[beneficiary], "Beneficiary is in black list");
    }

    /**
     * @notice 交易执行后进行的操作
     *          记录交易时间
     *          更新持有者统计
     *          触发分红逻辑
     * @param benefactor 交易发起方地址
     * @param beneficiary 交易接收方地址
     * @param amount 交易金额
     */
    function afterTransferHandler(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view override onlyOwner {
        // No operation after transfer
    }

    /**
     * @notice 添加黑名单
     * @param addr 地址
     */
    function addToBlackList(address addr) external onlyOwner {
        black_list[addr] = true;
    }

    /**
     * @notice 移除黑名单
     * @param addr 地址
     */
    function removeFromBlackList(address addr) external onlyOwner {
        black_list[addr] = false;
    }

    /**
     * @notice 批量添加黑名单
     * @param addrs 地址数组
     */
    function addBatchToBlackList(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            black_list[addrs[i]] = true;
        }
    }

    /**
     * @notice 批量移除黑名单
     * @param addrs 地址数组
     */
    function removeBatchFromBlackList(
        address[] calldata addrs
    ) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            black_list[addrs[i]] = false;
        }
    }
}
