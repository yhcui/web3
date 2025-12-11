pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

/**
 * @title UniswapV2ERC20
 * @dev Uniswap V2 的 ERC20 实现（用于 LP 代币）。
 *  该合约实现了标准的 ERC20 功能（转账/授权/余额管理），并额外支持 EIP-2612 风格的
 *  `permit`（基于 EIP-712 的签名授权），从而允许持有者通过签名离线授权 spender，
 *  无需发送链上 approve 交易即可授权。
 *
 *  注意：本文件为 core 实现的一部分，仅对注释进行了补充，未修改任何业务逻辑。
 */
contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;

    // ---- 代币元数据（常量） ----
    // 合约名/符号/小数位均为常量，实现上可声明为 `pure` 返回
    string public constant name = 'Uniswap V2';
    string public constant symbol = 'UNI-V2';
    uint8 public constant decimals = 18;

    // ---- ERC20 状态 ----
    // 总供应量
    uint  public totalSupply;
    // 地址余额映射
    mapping(address => uint) public balanceOf;
    // 允许额度 mapping: owner => (spender => amount)
    mapping(address => mapping(address => uint)) public allowance;

    // ---- EIP-2612 / EIP-712 相关 ----
    // 用于构造 EIP-712 digest 的 DOMAIN_SEPARATOR，包含合约地址和 chainId，防止跨合约/跨链重放
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    // 这是 permit 类型的 typehash，合约实现中用来计算 structHash
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // 每个地址的 nonce，用于防止签名重放；每次成功使用 permit 后自增
    mapping(address => uint) public nonces;

    // ---- 事件（遵循 ERC20） ----
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    /**
     * @dev 构造函数：初始化 `DOMAIN_SEPARATOR`，包含 EIP712 域数据（name/version/chainId/verifyingContract）
     */
    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    /**
     * @dev 内部铸币函数：增加 `to` 的余额并增加总供应量，触发 Transfer(from=0)
     */
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    /**
     * @dev 内部销毁函数：减少 `from` 的余额并减少总供应量，触发 Transfer(to=0)
     */
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    /**
     * @dev 内部 helper：设置 allowance 并发出 Approval 事件
     */
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @dev 内部 helper：执行从 `from` 到 `to` 的余额转移并发出 Transfer 事件
     */
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    /**
     * @notice 标准 ERC20 approve：允许 `spender` 花费调用者的 `value`
     * @return 返回是否成功
     */
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice 标准 ERC20 转账：将调用者的资产转给 `to`
     * @return 返回是否成功
     */
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice 标准 ERC20 转账（从 `from` 到 `to`），若 allowance 不是 uint(-1) 则会减少 allowance
     * @return 返回是否成功
     */
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice permit 实现（EIP-2612）：通过签名设置 `owner` 对 `spender` 的 allowance
     * @param owner 授权者（签名者）
     * @param spender 被授权者
     * @param value 授权额度
     * @param deadline 签名过期时间（timestamp）
     * @param v,r,s 签名三元组，用于 ecrecover 恢复签名者地址
     *
     * @dev 实现要点：
     *  - 检查 deadline 未过期
     *  - 使用 `nonces[owner]++`（后缀自增）与 `PERMIT_TYPEHASH` 构造 structHash
     *  - 使用 `DOMAIN_SEPARATOR` 与 structHash 构造 EIP-712 digest
     *  - 使用 ecrecover 恢复签名者地址并校验为 owner
     *  - 验证通过后调用内部 `_approve` 设置 allowance
     */
    /*
        deadline 由签名者（owner）在离线签名时确定并写入签名数据里；提交链上交易的通常是 relayer 或 spender，但他们不能修改签名内的 deadline，因为 deadline 已被包含在签名的 digest 中。
    */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        // deadline 在签名里，所以即便 relayer 想改也会导致签名无效。
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
