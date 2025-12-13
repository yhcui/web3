// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Tax handler interface
 * @dev Any class that implements this interface can be used for protocol-specific tax calculations.
 */
interface ITaxHandler {
    /**
     * @notice 计算交易税
     * @param benefactor 交易发起方地址
     * @param beneficiary 交易接收方地址
     * @param amount 交易金额
     * @return transferAmount 实际转账金额
     * @return lpAmount 分配给 LP 的税费金额
     * @return reflectAmount 分配给反射分红的税费金额
     * @return treasuryAmount 分配给金库的税费金额
     * @return burnAmount 销毁的税费金额
     */
    function getTax(
        address benefactor,
        address beneficiary,
        uint256 amount
    ) external view returns (uint256, uint256, uint256, uint256, uint256);
}
