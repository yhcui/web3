pragma solidity >=0.5.0;

interface IUniswapV1Exchange {
    // 查询指定地址的余额
    function balanceOf(address owner) external view returns (uint);
    
    // 从一个地址向另一个地址转移代币
    function transferFrom(address from, address to, uint value) external returns (bool);
    
    // 移除流动性池中的资金
    // 参数: 
    // - uint: 要移除的流动性数量
    // - uint: 最小期望获得的ETH数量
    // - uint: 最小期望获得的代币数量
    // - uint: 截止时间戳
    // 返回值:
    // - uint: 实际获得的ETH数量
    // - uint: 实际获得的代币数量
    function removeLiquidity(uint, uint, uint, uint) external returns (uint, uint);
    
    // 将代币兑换为ETH（输入模式）
    // 参数:
    // - uint: 输入的代币数量
    // - uint: 最小期望获得的ETH数量
    // - uint: 截止时间戳
    // 返回值:
    // - uint: 实际获得的ETH数量
    function tokenToEthSwapInput(uint, uint, uint) external returns (uint);
    
    // 将ETH兑换为代币（输入模式）
    // 参数:
    // - uint: 最小期望获得的代币数量
    // - uint: 截止时间戳
    // 返回值:
    // - uint: 实际获得的代币数量
    function ethToTokenSwapInput(uint, uint) external payable returns (uint);
}