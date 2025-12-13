// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITaxHandler} from "../interfaces/ITexHandler.sol";

contract TexHandler is ITaxHandler, Ownable {
    struct TaxRates {
        uint64 lpFee; // LP 注入
        uint64 reflectFee; // 反射分红
        uint64 treasuryFee; // 金库
        uint64 burnFee; // 销毁
    }

    TaxRates public buyTax; // 买入税
    TaxRates public sellTax; // 卖出税

    // 常量：基数为 1000，即 1% = 10
    uint256 public constant FEE_DENOMINATOR = 1000;

    constructor(address owner) Ownable(owner) {
        // 默认买入税: LP 2% + 反射 2% + 金库 1% + 销毁 1% = 6%
        buyTax = TaxRates({
            lpFee: 20,
            reflectFee: 20,
            treasuryFee: 10,
            burnFee: 10
        });

        // 默认卖出税: LP 3% + 反射 3% + 金库 2% + 销毁 2% = 10%
        sellTax = TaxRates({
            lpFee: 30,
            reflectFee: 30,
            treasuryFee: 20,
            burnFee: 20
        });
    }

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
    )
        external
        view
        onlyOwner
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        TaxRates memory tax;
        // 简单示例：假设 from 是交易所地址则为卖出，to 是交易所地址则为买入
        if (benefactor == owner()) {
            // 卖出
            tax = sellTax;
        } else if (beneficiary == owner()) {
            // 买入
            tax = buyTax;
        } else {
            // 普通转账不收税
            return (amount, 0, 0, 0, 0);
        }

        // 计算各项税费
        uint256 lpAmount = (amount * tax.lpFee) / FEE_DENOMINATOR;
        uint256 reflectAmount = (amount * tax.reflectFee) / FEE_DENOMINATOR;
        uint256 treasuryAmount = (amount * tax.treasuryFee) / FEE_DENOMINATOR;
        uint256 burnAmount = (amount * tax.burnFee) / FEE_DENOMINATOR;

        uint256 totalTax = lpAmount +
            reflectAmount +
            treasuryAmount +
            burnAmount;
        uint256 transferAmount = amount - totalTax;

        return (
            transferAmount,
            lpAmount,
            reflectAmount,
            treasuryAmount,
            burnAmount
        );
    }

    /**
     * @notice 设置买入税
     */
    function setBuyTax(
        uint64 lpFee,
        uint64 reflectFee,
        uint64 treasuryFee,
        uint64 burnFee
    ) public onlyOwner {
        buyTax = TaxRates({
            lpFee: lpFee,
            reflectFee: reflectFee,
            treasuryFee: treasuryFee,
            burnFee: burnFee
        });
    }

    /**
     * @notice 设置卖出税
     */
    function setSellTax(
        uint64 lpFee,
        uint64 reflectFee,
        uint64 treasuryFee,
        uint64 burnFee
    ) public onlyOwner {
        sellTax = TaxRates({
            lpFee: lpFee,
            reflectFee: reflectFee,
            treasuryFee: treasuryFee,
            burnFee: burnFee
        });
    }
}
