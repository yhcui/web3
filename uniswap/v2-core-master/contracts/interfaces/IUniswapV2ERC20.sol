pragma solidity >=0.5.0;

interface IUniswapV2ERC20 {
    /**
     * @dev ERC-20 标准事件：当 allowance 被设置/更改时触发
     * owner: 授权者
     * spender: 被授权者
     * value: 授权额度
     */
    event Approval(address indexed owner, address indexed spender, uint value);

    /**
     * @dev ERC-20 标准事件：当 token 从 `from` 转移到 `to` 时触发
     */
    event Transfer(address indexed from, address indexed to, uint value);

    /**
     * @notice 代币名称（对于 Uniswap LP token 实现通常为常量，因此声明为 `pure`）
     */
    function name() external pure returns (string memory);

    /**
     * @notice 代币符号（通常为常量，返回如 "UNI-V2"）
     */
    function symbol() external pure returns (string memory);

    /**
     * @notice 小数位数（通常为 18）
     */
    function decimals() external pure returns (uint8);

    /**
     * @notice 代币总供应量
     */
    function totalSupply() external view returns (uint);

    /**
     * @notice 查询某个地址的余额
     */
    function balanceOf(address owner) external view returns (uint);

    /**
     * @notice 查询 owner 授权给 spender 的额度
     */
    function allowance(address owner, address spender) external view returns (uint);

    /**
     * @notice 标准 ERC-20 授权：将调用方的 `spender` 授权为 `value`
     * @return 是否成功
     */
    function approve(address spender, uint value) external returns (bool);

    /**
     * @notice 标准 ERC-20 转账
     * @return 是否成功
     */
    function transfer(address to, uint value) external returns (bool);

    /**
     * @notice 标准 ERC-20 从 `from` 转账到 `to`（需有 allowance）
     * @return 是否成功
     */
    function transferFrom(address from, address to, uint value) external returns (bool);

    /* ------------------------------------------------------------------- */
    /* 以下为 Uniswap 特有的 permit（EIP-2612）相关接口，用于离线签名授权 */
    /* ------------------------------------------------------------------- */

    /**
     * @notice EIP-712 的 DOMAIN_SEPARATOR，用于签名域分隔，防止跨链/跨合约重放
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice permit 类型的 typehash，通常为 keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    /**
     * @notice 每个地址的 nonce，用于防止签名重放。每次成功使用 permit 后自增。
     */
    function nonces(address owner) external view returns (uint);

    /**
     * @notice 通过签名设置 allowance（EIP-2612）
     * @param owner 授权者地址（签名者）
     * @param spender 被授权者
     * @param value 授权额度
     * @param deadline 签名过期时间（timestamp），若超过则视为无效
     * @param v,r,s 签名的三个部分，用于 ecrecover 恢复签名者地址
     *
     * @dev 实现通常会：
     *  1. 检查 block.timestamp <= deadline
     *  2. 读取并使用 `nonces[owner]` 以及 `PERMIT_TYPEHASH`、`DOMAIN_SEPARATOR` 构造 EIP-712 digest
     *  3. 使用 `ecrecover` 恢复签名者并与 `owner` 比对
     *  4. 在验证通过后设置 allowance 并将 `nonces[owner]` 自增，防止重放
     */
    /*
    作用：permit 允许代币持有者通过签名（离线）授权他人花费自己代币，从而无需持有者发起链上 approve 交易并支付 gas。它基于 EIP-2612（用 EIP-712 的结构化签名）实现“免 gas 授权”。
    好处：用户体验更好（不用先 approve 再 transferFrom），减少一次交易的 gas 成本，支持 meta-transactions/relayer 场景。
    
    工作流程（高层）
    1、持有者（owner）在链下对一组数据签名，数据包含：owner、spender、value、nonce、deadline 等（类型由 PERMIT_TYPEHASH 定义）。
    2、任意人（通常是 spender 或 relayer）将签名（v,r,s）连同签名数据提交到链上，调用合约的 permit(...)。
    3、合约验证签名有效、未过期（deadline），并且 nonce 与当前 nonces[owner] 匹配。验证通过后，合约把 allowance[owner][spender] 设为 value（并通常触发 Approval 事件），同时把 nonces[owner] 增加 1，防止重放（replay）。
    关键字段解释（在 Uniswap 的接口中）

    DOMAIN_SEPARATOR()：EIP-712 的域分隔符（domain separator），通常包含合约名、版本、链 id、合约地址等，用来防止跨链/跨合约重放签名。
    PERMIT_TYPEHASH()：预计算的类型哈希（例如 EIP-2612 常用字符串 "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)" 的 keccak256）。
    nonces(address owner)：每个地址的递增计数器，用于防止签名重放。每次成功使用一次 permit 后对应的 nonce 自增。
    permit(owner, spender, value, deadline, v, r, s)：链上调用入口，把签名信息发给合约让合约去验证并设置 allowance。
    
    在前端/客户端生成签名（概念）

    1、使用 EIP-712 的签名方法（例如 ethers.js 的 _signTypedData(domain, types, value) 或 web3-provider 的 eth_signTypedData_v4）。
    2、domain 应包含与合约 DOMAIN_SEPARATOR 对应的字段（如 name、version、chainId、verifyingContract）。
    3、types 包含 Permit 类型定义（owner、spender、value、nonce、deadline）。
    4、value 是具体字段值。签名结果是 signature，可拆成 v, r, s 并提交给合约 permit(...)。

    调用流程（用户角度）
    1、DApp 获取 nonces[owner]、DOMAIN_SEPARATOR/chainId 等，构造签名域。
    2、用户在钱包中签名（无需支付 gas）。
    3、DApp 或 relayer 调用链上合约：IUniswapV2ERC20(pair).permit(owner, spender, value, deadline, v, r, s)。
    4、合约验证签名并设置 allowance，此后 spender 可以直接 transferFrom(owner, ...)。
    */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
