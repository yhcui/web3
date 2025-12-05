// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./governance/IGovernanceToken.sol";
import "./tax/ITaxHandler.sol";
import "./treasury/ITreasuryHandler.sol";

/**
 * @title Floki token contract
 * @dev The Floki token has modular systems for tax and treasury handler as well as governance capabilities.
 */
/*
代币经济学（ERC-20）、模块化税收（DeFi/AMM）、和 链上治理（DAO）
FLOKI 合约的核心业务目标是创建一个具备可持续资金来源、可灵活升级、并由社区驱动的代币生态系统。
支柱一：社区驱动的治理 (DAO)。这是 FLOKI 合约最复杂的业务逻辑，借鉴了 Compound/Uniswap 的治理模型。
支柱二、模块化代币经济学与税收 (Taxation & Treasury)。FLOKI 不是一个简单的 ERC-20 代币，它通过税收机制为协议金库提供资金，并利用模块化设计支持复杂的 DeFi 业务
支柱三：协议控制与转账钩子 (Transaction Hooks)。通过 ITreasuryHandler 接口，FLOKI 合约将自己嵌入到每一笔代币转账流程中，以便实现对交易行为的控制

FLOKI 合约中当前的代码实现只完成了 DAO 系统的 输入端（投票权统计），而输出端（实际的治理行为）是完全缺失的。
需要的缺失模块：
1. 提案系统 (Proposal Management)。核心治理合约，负责管理提案的生命周期（创建、排队、取消、执行）。
2. 时间锁与执行 (TimeLock & Execution)。一个特权合约，它负责接收通过投票的提案（调用），并在一个预定的延迟期（例如 48 小时）后执行它们。

FLOKI 代币合约代码中，税收机制的作用和金库资金的具体用途都没有被直接体现.FLOKI 代币合约本身只负责收钱并存入金库地址，但它不负责花钱或定义资金用途


在实际的加密项目中，由交易税收积累起来的金库资金通常用于以下几个核心业务领域：
1. 协议开发与维护
开发团队薪资: 支付给维护和升级协议智能合约、前端、后端基础设施的开发者。
审计费用: 支付给第三方安全公司，用于审计智能合约，确保代码安全。

2. 流动性与价格稳定
流动性提供 (LP): 购买代币和配对资产（如 ETH 或稳定币），用于在去中心化交易所（DEX）中增加流动性，从而减少大额交易的滑点。
回购与销毁 (Buyback & Burn): 从市场回购代币并销毁，减少总供应量，对代币价格产生通缩作用。

3. 市场营销与生态扩展
市场营销: 支付给广告、公关、社区活动和合作项目，以提高代币知名度和采用率。
合作投资: 投资于生态系统内的新项目，促进生态繁荣。
社区奖励/空投: 用于激励社区贡献者或进行空投活动。

4. 治理执行
在一个完整的 DAO 架构中，金库合约 (ITreasuryHandler 的实际实现) 必须包含允许 DAO 执行的函数，例如：
function distributeFunds(address destination, uint256 amount) external onlyGovernor;
function addLiquidity(uint256 amountA, uint256 amountB) external onlyGovernor;
这些函数只有在通过社区投票后，才能由 治理合约（Governor） 触发执行。因此，金库资金的用途最终是由 FLOKI 的 DAO 投票决定的。

*/
contract FLOKI is IERC20, IGovernanceToken, Ownable {
    /// @dev Registry of user token balances.
    // 存储每个地址的 代币余额。
    mapping(address => uint256) private _balances;

    /// @dev Registry of addresses users have given allowances to.
    // 存储授权信息（owner 授权 spender 可支配的金额）。
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice Registry of user delegates for governance.
    // 存储每个地址的 投票委托人（delegator -> delegatee）
    mapping(address => address) public delegates;

    /// @notice Registry of nonces for vote delegation.
    // 用于 delegateBySig 的 交易计数，防止重放攻击
    mapping(address => uint256) public nonces;

    /// @notice Registry of the number of balance checkpoints an account has.
    // 存储每个地址的快照点数量
    // nCheckpoints（即 numCheckpoints[address]）可以理解为一个委托人地址（delegatee）成功调用 _writeCheckpoint 函数的次数，
    // 而 _writeCheckpoint 是由 _moveDelegates 调用的。
    mapping(address => uint32) public numCheckpoints;

    /// @notice Registry of balance checkpoints per account.
    // 存储每个地址的历史投票快照点（区块号和投票数）
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The EIP-712 typehash for the contract's domain.
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract.
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The contract implementing tax calculations.
    // 税费处理合约的接口实例。
    ITaxHandler public taxHandler;

    /// @notice The contract that performs treasury-related operations.
    // 金库操作合约的接口实例。
    ITreasuryHandler public treasuryHandler;

    /// @notice Emitted when the tax handler contract is changed.
    event TaxHandlerChanged(address oldAddress, address newAddress);

    /// @notice Emitted when the treasury handler contract is changed.
    event TreasuryHandlerChanged(address oldAddress, address newAddress);

    /// @dev Name of the token.
    string private _name;

    /// @dev Symbol of the token.
    string private _symbol;

    /**
     * @param name_ Name of the token.
     * @param symbol_ Symbol of the token.
     * @param taxHandlerAddress Initial tax handler contract.
     * @param treasuryHandlerAddress Initial treasury handler contract.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address taxHandlerAddress,
        address treasuryHandlerAddress
    ) {
        _name = name_;
        _symbol = symbol_;

        taxHandler = ITaxHandler(taxHandlerAddress);
        treasuryHandler = ITreasuryHandler(treasuryHandlerAddress);

        _balances[_msgSender()] = totalSupply();

        emit Transfer(address(0), _msgSender(), totalSupply());
    }

    /**
     * @notice Get token name.
     * @return Name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @notice Get token symbol.
     * @return Symbol of the token.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Get number of decimals used by the token.
     * @return Number of decimals used by the token.
     */
    function decimals() external pure returns (uint8) {
        return 9;
    }

    /**
     * @notice Get the maximum number of tokens.
     * @return The maximum number of tokens that will ever be in existence.
     */
    function totalSupply() public pure override returns (uint256) {
        // Ten trillion, i.e., 10,000,000,000,000 tokens.
        return 1e13 * 1e9;
    }

    /**
     * @notice Get token balance of given given account.
     * @param account Address to retrieve balance for.
     * @return The number of tokens owned by `account`.
     */
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Transfer tokens from caller's address to another.
     * @param recipient Address to send the caller's tokens to.
     * @param amount The number of tokens to transfer to recipient.
     * @return True if transfer succeeds, else an error is raised.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @notice Get the allowance `owner` has given `spender`.
     * @param owner The address on behalf of whom tokens can be spent by `spender`.
     * @param spender The address authorized to spend tokens on behalf of `owner`.
     * @return The allowance `owner` has given `spender`.
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @notice Approve address to spend caller's tokens.
     * @dev This method can be exploited by malicious spenders if their allowance is already non-zero. See the following
     * document for details: https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM/edit.
     * Ensure the spender can be trusted before calling this method if they've already been approved before. Otherwise
     * use either the `increaseAllowance`/`decreaseAllowance` functions, or first set their allowance to zero, before
     * setting a new allowance.
     * @param spender Address to authorize for token expenditure.
     * @param amount The number of tokens `spender` is allowed to spend.
     * @return True if the approval succeeds, else an error is raised.
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another.
     * @param sender Address to move tokens from.
     * @param recipient Address to send the caller's tokens to.
     * @param amount The number of tokens to transfer to recipient.
     * @return True if the transfer succeeds, else an error is raised.
     */
    // 包含安全检查: 检查授权金额是否足够，并在转账后减少授权余额（使用 unchecked 块进行安全的减法）
    // transferFrom 函数是 ERC-20 代币标准中专门用于 授权消费 机制的核心函数。
    // 它的设计目的就是为了让被授权方（spender） 能够代替代币所有者（owner） 转移其代币
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "FLOKI:transferFrom:ALLOWANCE_EXCEEDED: Transfer amount exceeds allowance."
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @notice Increase spender's allowance.
     * @param spender Address of user authorized to spend caller's tokens.
     * @param addedValue The number of tokens to add to `spender`'s allowance.
     * @return True if the allowance is successfully increased, else an error is raised.
     */
    // 安全地增加（或增加）一个被授权方（spender）可以代表代币所有者（调用者 msg.sender）花费的代币额度（allowance）
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);

        return true;
    }

    /**
     * @notice Decrease spender's allowance.
     * @param spender Address of user authorized to spend caller's tokens.
     * @param subtractedValue The number of tokens to remove from `spender`'s allowance.
     * @return True if the allowance is successfully decreased, else an error is raised.
     */
    // 安全地减少一个被授权方（spender）可以代表代币所有者（调用者 msg.sender）花费的代币额度（allowance）
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "FLOKI:decreaseAllowance:ALLOWANCE_UNDERFLOW: Subtraction results in sub-zero allowance."
        );
        // unchecked 块: 在 Solidity 0.8.0 及更高版本中，标准的算术操作（加、减、乘）默认会检查溢出/下溢。
        // 但是，由于代码已经在第 2 步手动使用 require 进行了下溢检查，因此在这里使用 unchecked 块可以节省 Gas 费用，因为它告诉编译器不需要再进行一次内部检查。
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @notice Delegate votes to given address.
     * @dev It should be noted that users that want to vote themselves, also need to call this method, albeit with their
     * own address.
     * @param delegatee Address to delegate votes to.
     */
    // 允许调用者将自己的全部投票权委托给另一个地址 (delegatee)
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegate votes from signatory to `delegatee`.
     * @param delegatee The address to delegate votes to.
     * @param nonce The contract state required to match the signature.
     * @param expiry The time at which to expire the signature.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     */
    // delegateBySig 函数中实现 EIP-712 签名验证 的核心逻辑。它的目标是安全、可信地从链下签名数据中恢复出签名者的地址
    // 链下签名委托。允许用户在不发送交易的情况下，通过签名授权其他地址（如中继者）在链上提交委托交易
    // 当说 delegateBySig “允许用户在不发送交易的情况下完成委托” 时，这里的“用户”特指代币的实际所有者（signatory，即投票权的主人）
    // 传统委托 (delegate) 如果您直接调用 delegate(delegatee)：发送交易的人: 代币所有者（您自己）。成本: 您必须支付 Gas 费用。
    // 签名委托 (delegateBySig):代币所有者（您）的动作是：链下签名
    // 发送交易的人: 第三方中继者 (Relayer)。 中继者收到您的签名数据后，调用 delegateBySig 函数，并支付相应的 Gas 费用
    function delegateBySig(
        address delegatee, // 投票权将委托给的目标地址。
        uint256 nonce, // 交易计数器，用于防止签名被重复使用（重放攻击）
        uint256 expiry, // 签名失效的时间戳
        uint8 v, // 
        bytes32 r,
        bytes32 s
    ) external {
        // EIP-712 签名验证逻辑详解。整个过程分为三个主要步骤：构建域分隔符、构建结构体哈希，以及将两者结合并恢复地址
        // 构建 Domain Separator（域分隔符）
        // 这是验证过程的上下文层，目的是将签名绑定到特定的合约和区块链，防止签名被恶意用于其他合约或网络（即防重放攻击）
        // 将所有参数一起进行哈希，生成一个独一无二的 domainSeparator。如果任何一个参数不同（比如在不同的链上），则这个域分隔符就会不同，签名验证就会失败
        bytes32 domainSeparator = keccak256(
            // DOMAIN_TYPEHASH: 这是一个固定的哈希值，代表 EIP-712 域的结构定义（EIP712Domain(string name,uint256 chainId,address verifyingContract)）
            // keccak256(bytes(name())): 当前代币合约的名称（例如 "FLOKI"）的哈希值。
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), block.chainid, address(this))
        );
        
        // 验证过程的数据层，目的是对用户实际想要执行的操作细节进行结构化哈希
        // DELEGATION_TYPEHASH: 代表用户正在执行的操作类型定义（Delegation(address delegatee,uint256 nonce,uint256 expiry)）
        // delegatee: 用户想要委托投票权给谁。
        // nonce: 用于防止签名被重复使用的计数器。
        // expiry: 签名失效的时间戳
        // 将操作数据和类型哈希一起进行哈希，生成 structHash，确保用户签署的就是这些特定的参数
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));

        // 计算 Digest 并恢复地址。这是最终的验证步骤，将上下文和数据结合起来，并利用内置的密码学函数恢复签名者的地址
        // \x19\x01: 这是一个固定的 EIP-712 前缀，用于防止签名被用作以太坊原生交易哈希
        // abi.encodePacked: 将前缀、domainSeparator 和 structHash 紧密地连接在一起，并进行最终的哈希。这个 digest 就是用户在链下用私钥签署的最终数据
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // 输出签署该内容的原始以太坊地址（即 signatory）.
        // signatory 成功恢复出一个非零地址，并且该地址是预期的代币所有者，则证明签名有效，且未被篡改
        address signatory = ecrecover(digest, v, r, s);

        /*
        Solidity 提供了多种编码方式，它们在如何处理数据填充（padding）和数据类型上有所不同。
        abi.encode (Standard ABI)	
        填充 (Padding)	是。所有数据类型（包括地址、整数、哈希）都会被填充到 32 字节（256 位）。
        主要用途1. 外部函数调用 (Call Data)。2. 事件参数编码。3. EIP-712 结构体哈希。

        abi.encodePacked (Packed Mode)
        填充 (Padding)	否。数据会尽可能紧凑地连接在一起，没有 32 字节填充。
        主要用途1. Keccak256 哈希输入 (如计算唯一 ID)。2. 构建 EIP-712 Digest。

        使用 abi.encode (用于结构化数据哈希)。在构建 domainSeparator 和 structHash 时，使用的是 abi.encode
        为什么使用 abi.encode？
        1、EIP-712 规范要求：EIP-712 规范要求在对结构体进行哈希时，必须使用标准 ABI 编码。
        2、消除歧义：标准 ABI 编码（32 字节填充）确保了即使不同的数据组合在一起，它们的编码结果也是唯一的，从而防止了哈希冲突或编码歧义。
        3、结构体哈希的用途：确保签名的用户和验证的合约对结构体中的每个字段（如 delegatee、nonce、expiry）的类型和位置有明确、统一的理解。


        使用 abi.encodePacked (用于最终摘要的紧凑连接)
        在计算最终的 digest 时，使用的是 abi.encodePacked
        为什么使用 abi.encodePacked？
        1、EIP-712 规范要求：EIP-712 规范要求最终的签名摘要 (digest) 是由固定的前缀、domainSeparator 和 structHash 紧密连接后再哈希得到的。
        2、效率与简洁：domainSeparator 和 structHash 本身已经是 32 字节的 bytes32 类型。使用 abi.encodePacked 可以直接将它们与 \x19\x01 这个字节序列无缝拼接，而不会引入额外的 32 字节填充或偏移量，从而生成规范要求的紧凑字节串

        为什么需要进行 Encoding（编码）？
        对数据进行编码和哈希处理，是保证区块链安全性和可验证性的核心机制：
        数据的唯一表示：将复杂的结构化数据（地址、字符串、数字）转换成一个唯一的、不可逆的 32 字节哈希值。
        数据完整性：在验证签名时，合约需要重建与用户签署时完全相同的原始数据。编码方法（无论是标准 ABI 还是 Packed）确保了链上和链下对数据的解释是一致的。
        防止篡改：如果不对数据进行编码和哈希，用户签署的可能只是原始数据的一个子集。哈希确保了用户对整个数据结构负责

        */

        require(signatory != address(0), "FLOKI:delegateBySig:INVALID_SIGNATURE: Received signature was invalid.");
        require(block.timestamp <= expiry, "FLOKI:delegateBySig:EXPIRED_SIGNATURE: Received signature has expired.");
        require(nonce == nonces[signatory]++, "FLOKI:delegateBySig:INVALID_NONCE: Received nonce was invalid.");

        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Determine the number of votes for an account as of a block number.
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check.
     * @param blockNumber The block number to get the vote balance at.
     * @return The number of votes the account had as of the given block.
     */
    // 实现 历史投票快照查询 的核心逻辑。它允许任何人在不修改链上状态的情况下，查询某个地址在过去特定区块拥有的投票权重
    // 检索 account 地址在指定的 blockNumber 时拥有的投票数。
    function getVotesAtBlock(address account, uint32 blockNumber) public view returns (uint224) {

        // 检查 1: 拒绝查询未来的区块
        require(
            blockNumber < block.number,
            "FLOKI:getVotesAtBlock:FUTURE_BLOCK: Cannot get votes at a block in the future."
        );

        //  检查 2: 如果该账户没有任何快照记录
        // nCheckpoints 变量指的是一个特定地址（account）在链上记录的投票快照（Checkpoint）的总数量
        uint32 nCheckpoints = numCheckpoints[account];
        // 无快照记录: 如果 numCheckpoints 为 0，说明该地址从未进行过转账或委托操作，其投票数自然为 0.
        // 返回
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance.
        // 如果请求查询的区块号（blockNumber）晚于或等于最新快照记录的区块号，则直接返回最新记录的投票数，从而跳过复杂的二分查找过程。
        // 为什么可以直接返回最新记录的投票数？ 一个地址的投票数，一旦被记录在某个快照点，就会保持不变，直到合约触发另一个事件并创建下一个快照
        // 原则： 一个委托人地址的投票数，在创建新的快照之前，将一直保持不变。
        if (checkpoints[account][nCheckpoints - 1].blockNumber <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance.
        // 查询最早快照被创建时的区块号之前的投票数
        if (checkpoints[account][0].blockNumber > blockNumber) {
            return 0;
        }

        // 只有当目标区块号 blockNumber介于该账户的第一个快照和最后一个快照的区块号之间时，才会执行上述二分查找代码

        // Perform binary search.
        // 二分查询对应的区块
        uint32 lowerBound = 0;
        uint32 upperBound = nCheckpoints - 1;
        while (upperBound > lowerBound) {
            uint32 center = upperBound - (upperBound - lowerBound) / 2;
            Checkpoint memory checkpoint = checkpoints[account][center];

            if (checkpoint.blockNumber == blockNumber) {
                return checkpoint.votes;
            } else if (checkpoint.blockNumber < blockNumber) {
                lowerBound = center;
            } else {
                upperBound = center - 1;
            }
        }

        // No exact block found. Use last known balance before that block number.
        return checkpoints[account][lowerBound].votes;
    }

    /**
     * @notice Set new tax handler contract.
     * @param taxHandlerAddress Address of new tax handler contract.
     */
    function setTaxHandler(address taxHandlerAddress) external onlyOwner {
        address oldTaxHandlerAddress = address(taxHandler);
        taxHandler = ITaxHandler(taxHandlerAddress);

        emit TaxHandlerChanged(oldTaxHandlerAddress, taxHandlerAddress);
    }

    /**
     * @notice Set new treasury handler contract.
     * @param treasuryHandlerAddress Address of new treasury handler contract.
     */
    function setTreasuryHandler(address treasuryHandlerAddress) external onlyOwner {
        address oldTreasuryHandlerAddress = address(treasuryHandler);
        treasuryHandler = ITreasuryHandler(treasuryHandlerAddress);

        emit TreasuryHandlerChanged(oldTreasuryHandlerAddress, treasuryHandlerAddress);
    }

    /**
     * @notice Delegate votes from one address to another.
     * @param delegator Address from which to delegate votes for.
     * @param delegatee Address to delegate votes to.
     */
    // 投票权委托（Delegation） 负责更改委托关系，并将委托人（delegator）所持有的全部代币对应的投票权，从当前的委托人移动到新的委托人
    // 将一个地址的投票权永久地（直到再次委托）委托给另一个地址
    // delegator:委托人（代币的实际所有者）。
    // delegatee:。新的被委托人（接收投票权的地址）
    function (address delegator, address delegatee) private {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = _balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, uint224(delegatorBalance));
    }

    /**
     * @notice Move delegates from one address to another.
     * @param from Representative to move delegates from.
     * @param to Representative to move delegates to.
     * @param amount Number of delegates to move.
     */
    // 该函数在两个主要场景下被调用：
    // 代币转账 (_transfer): 当代币从地址 A 转移到地址 B 时，这笔代币对应的投票权会从 A 的委托人 转移到 B 的委托人。
    // 委托变更 (_delegate): 当用户将他们的投票权委托给一个新的地址时，他们的投票权会从旧的委托人转移到新的委托人。
    function _moveDelegates(
        address from, // 投票权转出方
        address to, // 投票权转入方
        uint224 amount // 发生转移的投票数量。
    ) private {
        // No need to update checkpoints if the votes don't actually move between different delegates. This can be the
        // case where tokens are transferred between two parties that have delegated their votes to the same address.
        if (from == to) {
            return;
        }

        // Some users preemptively delegate their votes (i.e. before they have any tokens). No need to perform an update
        // to the checkpoints in that case.
        if (amount == 0) {
            return;
        }

        if (from != address(0)) {
            // 减少旧委托人的投票数
            uint32 fromRepNum = numCheckpoints[from];
            // checkpoints[from][fromRepNum - 1].votes  获取当前委托人（from）在本次投票权变动发生之前的总投票数 
            uint224 fromRepOld = fromRepNum > 0 ? checkpoints[from][fromRepNum - 1].votes : 0;
            uint224 fromRepNew = fromRepOld - amount;

            _writeCheckpoint(from, fromRepNum, fromRepOld, fromRepNew);
        }

        if (to != address(0)) {
            // 增加新委托人的投票数
            uint32 toRepNum = numCheckpoints[to];
            uint224 toRepOld = toRepNum > 0 ? checkpoints[to][toRepNum - 1].votes : 0;
            uint224 toRepNew = toRepOld + amount;

            _writeCheckpoint(to, toRepNum, toRepOld, toRepNew);
        }
    }

    /**
     * @notice Write balance checkpoint to chain.
     * @param delegatee The address to write the checkpoint for.
     * @param nCheckpoints The number of checkpoints `delegatee` already has.
     * @param oldVotes Number of votes prior to this checkpoint.
     * @param newVotes Number of votes `delegatee` now has.
     */
    // 记录委托人（delegatee）在当前区块的最新总投票数，并维护快照数组的长度。
    function _writeCheckpoint(
        address delegatee, // 投票数发生变化的委托人地址
        uint32 nCheckpoints, // 传入时，是该地址当前已有的快照记录总数（即 numCheckpoints[delegatee] 的旧值）。
        uint224 oldVotes,
        uint224 newVotes
    ) private {
        uint32 blockNumber = uint32(block.number);

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].blockNumber == blockNumber) {
            // 覆盖最新快照（同一区块去重）
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            // 新增快照记录
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    /**
     * @notice Approve spender on behalf of owner.
     * @param owner Address on behalf of whom tokens can be spent by `spender`.
     * @param spender Address to authorize for token expenditure.
     * @param amount The number of tokens `spender` is allowed to spend.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "FLOKI:_approve:OWNER_ZERO: Cannot approve for the zero address.");
        require(spender != address(0), "FLOKI:_approve:SPENDER_ZERO: Cannot approve to the zero address.");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Transfer `amount` tokens from account `from` to account `to`.
     * @param from Address the tokens are moved out of.
     * @param to Address the tokens are moved to.
     * @param amount The number of tokens to transfer.
     */
    // 代币的核心转账函数，集成了税费和治理逻辑
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "FLOKI:_transfer:FROM_ZERO: Cannot transfer from the zero address.");
        require(to != address(0), "FLOKI:_transfer:TO_ZERO: Cannot transfer to the zero address.");
        require(amount > 0, "FLOKI:_transfer:ZERO_AMOUNT: Transfer amount must be greater than zero.");
        require(amount <= _balances[from], "FLOKI:_transfer:INSUFFICIENT_BALANCE: Transfer amount exceeds balance.");
        // 允许金库合约在转账前执行操作（例如检查转账冷却时间）
        treasuryHandler.beforeTransferHandler(from, to, amount);

        //税费计算
        uint256 tax = taxHandler.getTax(from, to, amount);
        uint256 taxedAmount = amount - tax;

        _balances[from] -= amount;
        _balances[to] += taxedAmount;
        _moveDelegates(delegates[from], delegates[to], uint224(taxedAmount));

        if (tax > 0) {
            _balances[address(treasuryHandler)] += tax;

            _moveDelegates(delegates[from], delegates[address(treasuryHandler)], uint224(tax));

            emit Transfer(from, address(treasuryHandler), tax);
        }

        treasuryHandler.afterTransferHandler(from, to, amount);

        emit Transfer(from, to, taxedAmount);
    }
}