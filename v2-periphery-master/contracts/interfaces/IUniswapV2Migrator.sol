pragma solidity >=0.5.0;

interface IUniswapV2Migrator {
    /**
     * @dev 迁移流动性从旧版本到新版本
     * @param token 代币地址
     * @param amountTokenMin 最小代币数量
     * @param amountETHMin 最小ETH数量
     * @param to 接收地址
     * @param deadline 截止时间
     */
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}