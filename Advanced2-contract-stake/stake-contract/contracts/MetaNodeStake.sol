// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MetaNodeStake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    // ************************************** INVARIANT **************************************

    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");

    uint256 public constant ETH_PID = 0;

    // ************************************** DATA STRUCTURE **************************************
    /*
    Basically, any point in time, the amount of MetaNodes entitled to a user but is pending to be distributed is:

    pending MetaNode = (user.stAmount * pool.accMetaNodePerST) - user.finishedMetaNode

    Whenever a user deposits or withdraws staking tokens to a pool. Here's what happens:
    1. The pool's `accMetaNodePerST` (and `lastRewardBlock`) gets updated.
    2. User receives the pending MetaNode sent to his/her address.
    3. User's `stAmount` gets updated.
    4. User's `finishedMetaNode` gets updated.
    */
    struct Pool {
        // Address of staking token
        // 质押代币的地址
        address stTokenAddress;
        // Weight of pool
        // 不同资金池所占的权重
        uint256 poolWeight;
        // Last block number that MetaNodes distribution occurs for pool
        uint256 lastRewardBlock;
        // Accumulated MetaNodes per staking token of pool
        // 质押 1个ETH经过1个区块高度，能拿到 n 个MetaNode
        // accMetaNodePerST 的完整意思是 Accumulated MetaNode Per ST Token（每单位 ST Token 累计的 MetaNode 奖励）
        // pool_.accMetaNodePerST 这个值（全局累计率）在正常的 MasterChef 质押合约中是单调递增的，它不会下降。
        // pool_.accMetaNodePerST 代表着每质押 1 个 ST Token 累计应获得的 MetaNode 奖励总量。它的增长机制完全基于奖励的累积
        /*
        1. 增长机制回顾它的计算公式：
        $$\text{新 } R = \text{旧 } R + \frac{\text{该池子获得的 MetaNode 总奖励} \times 10^{18}}{\text{池子总质押量}}$$
        一、只要以下条件成立，就会增长：
        1、有区块时间流逝：奖励系统仍在 startBlock 和 endBlock 之间运行。
        2、有总奖励产生：getMultiplier 函数返回的值大于 0。
        3、池子中有质押：pool_.stTokenAmount (总质押量) 大于 0。
        每次用户与合约交互（如 deposit, unstake, claim）或管理员调用 setPoolWeight，都会触发 updatePool，计算这段时间流逝产生的奖励，然后将奖励增量累加到 accMetaNodePerST 上。由于是累加，所以它会持续增长。
        二、 不会下降的原因
        在标准的 MasterChef 模型中，没有任何机制会从 accMetaNodePerST 中减去数值：
        1、用户提款：当用户提款 ST Token 时，他们的新快照 (finishedMetaNode) 会被重置，但 pool_.accMetaNodePerST 本身不会减少。
        2、奖励领取：用户领取奖励时，合约只是将 accMetaNodePerST 作为一个参照物来计算差额，然后重置用户的个人快照，也不会减少 pool_.accMetaNodePerST。
        3、惩罚机制：除非合约被设计了特殊的销毁或惩罚机制（例如，收取费用来减少总质押量，或者在极端情况下被管理员手动归零），否则这个值在逻辑上是不会倒退的。在正常的质押逻辑中，它永远是一个不断增长的奖励“里程表”。
        */
        uint256 accMetaNodePerST;
        // Staking token amount
        // 质押的代币数量
        uint256 stTokenAmount;
        // Min staking amount
        // 最小质押数量
        uint256 minDepositAmount;
        // Withdraw locked blocks
        // Unstake locked blocks 解质押锁定的区块高度
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest {
        // Request withdraw amount
        uint256 amount; // 用户取消质押的代币数量，要取出多少个 token
        // The blocks when the request withdraw amount can be released
        uint256 unlockBlocks; // 解质押的区块高度
    }

    struct User {
        // 记录用户相对每个资金池 的质押记录
        // Staking token amount that user provided
        // 用户在当前资金池，质押的代币数量
        uint256 stAmount;
        // Finished distributed MetaNodes to user 最终 MetaNode 得到的数量
        // 用户在当前资金池，已经领取的 MetaNode 数量
        uint256 finishedMetaNode;
        // Pending to claim MetaNodes 当前可取数量
        // 用户在当前资金池，当前可领取的 MetaNode 数量
        uint256 pendingMetaNode;
        // Withdraw request list
        // 用户在当前资金池，取消质押的记录
        UnstakeRequest[] requests;
    }

    // ************************************** STATE VARIABLES **************************************
    // First block that MetaNodeStake will start from
    uint256 public startBlock; // 质押开始区块高度
    // First block that MetaNodeStake will end from
    uint256 public endBlock; // 质押结束区块高度
    // MetaNode token reward per block
    uint256 public MetaNodePerBlock; // 每个区块高度，MetaNode 的奖励数量

    // Pause the withdraw function
    bool public withdrawPaused; // 是否暂停提现
    // Pause the claim function
    bool public claimPaused; // 是否暂停领取

    // MetaNode token
    IERC20 public MetaNode; // MetaNode 代币地址

    // Total pool weight / Sum of all pool weights
    uint256 public totalPoolWeight; // 所有资金池的权重总和
    Pool[] public pool; // 资金池列表

    // pool id => user address => user info
    mapping(uint256 => mapping(address => User)) public user; // 资金池 id => 用户地址 => 用户信息

    // ************************************** EVENT **************************************

    event SetMetaNode(IERC20 indexed MetaNode);

    event PauseWithdraw();

    event UnpauseWithdraw();

    event PauseClaim();

    event UnpauseClaim();

    event SetStartBlock(uint256 indexed startBlock);

    event SetEndBlock(uint256 indexed endBlock);

    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);

    event AddPool(
        address indexed stTokenAddress,
        uint256 indexed poolWeight,
        uint256 indexed lastRewardBlock,
        uint256 minDepositAmount,
        uint256 unstakeLockedBlocks
    );

    event UpdatePoolInfo(
        uint256 indexed poolId,
        uint256 indexed minDepositAmount,
        uint256 indexed unstakeLockedBlocks
    );

    event SetPoolWeight(
        uint256 indexed poolId,
        uint256 indexed poolWeight,
        uint256 totalPoolWeight
    );

    event UpdatePool(
        uint256 indexed poolId,
        uint256 indexed lastRewardBlock,
        uint256 totalMetaNode
    );

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    event RequestUnstake(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 indexed blockNumber
    );

    event Claim(
        address indexed user,
        uint256 indexed poolId,
        uint256 MetaNodeReward
    );

    // ************************************** MODIFIER **************************************

    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    /**
     * @notice Set MetaNode token address. Set basic info when deploying.
     * 
     */
    // initializer: 这是一个特殊的 OpenZeppelin 修改器（Modifier），确保这个函数只在合约的生命周期内被调用一次。这是防止在可升级合约中重复初始化存储状态的关键安全措施
    function initialize(
        IERC20 _MetaNode, // 质押系统需要发放的奖励代币类型
        uint256 _startBlock, // MetaNode 奖励开始发放的区块高度
        uint256 _endBlock, // MetaNode 奖励停止发放的区块高度
        uint256 _MetaNodePerBlock // 基础奖励速率：每产生一个新区块，合约将发放的基础 MetaNode 数量
    ) public initializer {
        require(
            _startBlock <= _endBlock && _MetaNodePerBlock > 0,
            "invalid parameters"
        );

        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        setMetaNode(_MetaNode);

        startBlock = _startBlock;
        endBlock = _endBlock;
        MetaNodePerBlock = _MetaNodePerBlock;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADE_ROLE) {}

    // ************************************** ADMIN FUNCTION **************************************

    /**
     * @notice Set MetaNode token address. Can only be called by admin
     */
    function setMetaNode(IERC20 _MetaNode) public onlyRole(ADMIN_ROLE) {
        MetaNode = _MetaNode;

        emit SetMetaNode(MetaNode);
    }

    /**
     * @notice Pause withdraw. Can only be called by admin.
     */
    // 允许拥有特定权限的管理员临时禁用用户从合约中取出已解锁的质押代币 (withdraw) 的操作，通常用于紧急安全维护或升级
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");

        withdrawPaused = true;

        emit PauseWithdraw();
    }

    /**
     * @notice Unpause withdraw. Can only be called by admin.
     */
    // 允许管理员解除提款锁定，让用户可以再次调用 withdraw 来取回资金
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");

        withdrawPaused = false;

        emit UnpauseWithdraw();
    }

    /**
     * @notice Pause claim. Can only be called by admin.
     */
    // 暂停用户领取 MetaNode 奖励
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    /**
     * @notice Unpause claim. Can only be called by admin.
     */
    // 恢复用户领取 MetaNode 奖励
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }

    /**
     * @notice Update staking start block. Can only be called by admin.
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(
            _startBlock <= endBlock,
            "start block must be smaller than end block"
        );

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice Update staking end block. Can only be called by admin.
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(
            startBlock <= _endBlock,
            "start block must be smaller than end block"
        );

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice Update the MetaNode reward amount per block. Can only be called by admin.
     */
    function setMetaNodePerBlock(
        uint256 _MetaNodePerBlock
    ) public onlyRole(ADMIN_ROLE) {
        require(_MetaNodePerBlock > 0, "invalid parameter");

        MetaNodePerBlock = _MetaNodePerBlock;

        emit SetMetaNodePerBlock(_MetaNodePerBlock);
    }

    /**
     * @notice Add a new staking to pool. Can only be called by admin
     * DO NOT add the same staking token more than once. MetaNode rewards will be messed up if you do
     */
    // 允许合约的管理员向质押系统添加一个新的资金池（Pool），并配置其奖励权重和锁定参数
    function addPool(
        address _stTokenAddress, // 质押代币地址：用户将质押的 ERC-20 代币地址。
        uint256 _poolWeight, // 池子权重：该池子从总奖励中分配的相对份额。权重越高，获得的 MetaNode 奖励越多。
        uint256 _minDepositAmount, // 最小质押量：用户首次存入该池子所需的最小代币数量
        uint256 _unstakeLockedBlocks, // 取消质押锁定期：从用户发起 unstake 到可以调用 withdraw 取回资金之间，必须等待的区块数量。
        bool _withUpdate // 是否更新所有池子：如果为 true，则在添加新池子之前，会先结算所有现有池子的奖励。
    ) public onlyRole(ADMIN_ROLE) {
        // Default the first pool to be ETH pool, so the first pool must be added with stTokenAddress = address(0x0)
        // 第一个池子（pool.length == 0） 必须使用 address(0x0) (空地址) 作为质押代币地址。在 EVM 约定中，address(0x0) 通常代表 以太币 (ETH)。因此，PID 0 被预留给了 ETH 质押。
        if (pool.length > 0) {
            require(
                _stTokenAddress != address(0x0),
                "invalid staking token address"
            );
        } else {
            require(
                _stTokenAddress == address(0x0),
                "invalid staking token address"
            );
        }
        // allow the min deposit amount equal to 0
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        // 锁定期检查： 强制要求取消质押的锁定期 (_unstakeLockedBlocks) 必须大于 0。这意味着一旦质押，用户必须等待至少一个区块才能取回资金
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        // 奖励期检查： 确保当前区块高度小于奖励结束区块 (endBlock)。如果在奖励结束后添加池子，则没有意义
        require(block.number < endBlock, "Already ended");

        // 这是 MasterChef 模型中的最佳实践。如果管理员在奖励发放期间添加新的池子或修改权重，必须先结算所有现有池子的奖励。这防止了奖励在新权重生效时被不公平地分配或稀释。
        if (_withUpdate) {
            massUpdatePools();
        }

        // 新池子的奖励计算起点被设定为当前区块 (block.number) 或 奖励开始区块 (startBlock) 之间的较大者。这确保了新池子不会在奖励开始之前就开始计息
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;

        // 将新池子的权重 (_poolWeight) 累加到全局的 totalPoolWeight 上，从而改变奖励在所有池子之间的分配比例
        totalPoolWeight = totalPoolWeight + _poolWeight;

        // 通过 pool.push(...) 操作，新池子被添加到动态数组 pool 的末尾。新池子的 索引（pool.length 之前的长度） 就是它的 Pool ID (_pid)
        pool.push(
            Pool({
                stTokenAddress: _stTokenAddress,
                poolWeight: _poolWeight,
                lastRewardBlock: lastRewardBlock,
                accMetaNodePerST: 0,
                stTokenAmount: 0,
                minDepositAmount: _minDepositAmount,
                unstakeLockedBlocks: _unstakeLockedBlocks
            })
        );

        emit AddPool(
            _stTokenAddress,
            _poolWeight,
            lastRewardBlock,
            _minDepositAmount,
            _unstakeLockedBlocks
        );
    }

    /**
     * @notice Update the given pool's info (minDepositAmount and unstakeLockedBlocks). Can only be called by admin.
     */
    function updatePool(
        uint256 _pid, // 池子 ID：指定要修改哪个质押池
        uint256 _minDepositAmount, // 新的最小质押量：新的最低存款金额
        uint256 _unstakeLockedBlocks // 新的取消质押锁定期：新的取消质押后必须等待的区块数量。
    ) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pool[_pid].minDepositAmount = _minDepositAmount;
        pool[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;

        emit UpdatePoolInfo(_pid, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @notice Update the given pool's weight. Can only be called by admin.
     */
    function setPoolWeight(
        uint256 _pid, // 池子 ID：指定要修改哪个质押池。
        uint256 _poolWeight, // 新的权重值：该池子在所有池子总权重中所占的比例。
        bool _withUpdate // 是否更新所有池子：决定是否在修改权重前，先结算所有现有池子的奖励。
    ) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "invalid pool weight");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    // ************************************** QUERY FUNCTION **************************************

    /**
     * @notice Get the length/amount of pool
     */
    function poolLength() external view returns (uint256) {
        return pool.length;
    }

    /**
     * @notice Return reward multiplier over given _from to _to block. [_from, _to)
     *
     * @param _from    From block number (included)
     * @param _to      To block number (exluded)
     * getMultiplier(pool_.lastRewardBlock, block.number).tryMul(pool_.poolWeight);
     */
    // 用于计算在两个区块高度之间，总共应该发放多少 MetaNode 基础奖励。
    // 这个函数确保了奖励只在预定的奖励期 (startBlock 到 endBlock) 内产生
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256 multiplier) {
        // 这个函数确保了奖励只在预定的奖励期 (startBlock 到 endBlock) 内产生
        require(_from <= _to, "invalid block");

        // 起始边界: 如果传入的起始区块 (_from) 早于合约设定的奖励开始区块 (startBlock)，则将起始点强制设置为 startBlock。这意味着在奖励期开始前，不会计算奖励
        if (_from < startBlock) {
            _from = startBlock;
        }
        // 结束边界: 如果传入的结束区块 (_to) 晚于合约设定的奖励结束区块 (endBlock)，则将结束点强制设置为 endBlock。这意味着在奖励期结束后，不会再计算奖励
        if (_to > endBlock) {
            _to = endBlock;
        }

        // 最终检查: require(_from <= _to) 是一个额外的安全检查，确保经过调整后的 _from 和 _to 仍然保持正确的顺序，避免出现奖励期结束后仍试图计算负数奖励的情况。
        require(_from <= _to, "end block must be greater than start block");
        bool success;
        // 计算奖励区块数: (_to - _from) 得到在奖励期内经过的区块数量。
        // tryMul(MetaNodePerBlock) 将区块数乘以基础奖励速率 (MetaNodePerBlock)，得出这段时间间隔内应该发放的总 MetaNode 奖励数量
        (success, multiplier) = (_to - _from).tryMul(MetaNodePerBlock);
        
        // 确保乘法操作不会导致 溢出 (Overflow)
        require(success, "multiplier overflow");
    }

    /**
     * @notice Get pending MetaNode amount of user in pool
     */
    // 查询用户在特定质押池（Pool）中当前累计的、可领取但尚未转账的 MetaNode 奖励总量。
    function pendingMetaNode(
        uint256 _pid, // 要查询的质押池 ID。
        address _user // 要查询的用户地址
    ) external view checkPid(_pid) returns (uint256) {
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }

    /**
     * @notice Get pending MetaNode amount of user by block number in pool
     */
    // MasterChef 模型中懒惰结算（Lazy Calculation） 的核心函数。
    // 它的作用是在不实际修改合约状态的情况下，模拟 一次奖励更新，并计算用户在该模拟状态下的全部可领取奖励
    function pendingMetaNodeByBlockNumber(
        uint256 _pid,
        address _user,
        uint256 _blockNumber
    ) public view checkPid(_pid) returns (uint256) {
        // 从存储中加载当前池子和用户的状态
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        // accMetaNodePerST 的完整意思是 Accumulated MetaNode Per ST Token（每单位 ST Token 累计的 MetaNode 奖励）
        uint256 accMetaNodePerST = pool_.accMetaNodePerST;
        // 代表的是当前这个质押池中，所有用户质押的 ST Token 的总数量。
        uint256 stSupply = pool_.stTokenAmount;

        if (_blockNumber > pool_.lastRewardBlock && stSupply != 0) {
            // 1. 计算区块间隔的总奖励
            uint256 multiplier = getMultiplier(
                pool_.lastRewardBlock,
                _blockNumber
            );
            // 2. 根据权重分配该池子的份额
            // MetaNodeForPool:该池子在本次结算的区块间隔内，从总产出中分配到的 MetaNode 奖励总额
            uint256 MetaNodeForPool = (multiplier * pool_.poolWeight) /
                totalPoolWeight;

            // 在当前奖励周期内，每质押 1 个 ST Token 应该增加多少 MetaNode 奖励，并将其累加到全局累计率 R上
            // MetaNodeForPool：这个变量代表的是在 pool_.lastRewardBlock 到 block.number 之间，新产生的 MetaNode 奖励中，分配给该池子的总数量。
            // 它是一个全新的、尚未计入 accMetaNodePerST 的奖励量。是纯粹的增量，它本身不包含任何历史
            accMetaNodePerST =
                accMetaNodePerST +
                (MetaNodeForPool * (1 ether)) /
                stSupply;
        }

        // 当前累计总收益：(user_.stAmount * accMetaNodePerST) / (1 ether)
        // 减去已结算起点：- user_.finishedMetaNode。减去用户上次操作时设置的奖励快照点
        // 加上旧待领余额：+ user_.pendingMetaNode
        return
            (user_.stAmount * accMetaNodePerST) /
            (1 ether) -
            user_.finishedMetaNode +
            user_.pendingMetaNode;
    }

    /**
     * @notice Get the staking amount of user
     */
    // 获取特定用户在指定质押池中的当前质押量
    function stakingBalance(
        uint256 _pid,
        address _user
    ) external view checkPid(_pid) returns (uint256) {
        return user[_pid][_user].stAmount;
    }

    /**
     * @notice Get the withdraw amount info, including the locked unstake amount and the unlocked unstake amount
     */
    function withdrawAmount(
        uint256 _pid,
        address _user
    )
        public
        view
        checkPid(_pid)
        returns (uint256 requestAmount, uint256 pendingWithdrawAmount)
    {
        // requestAmount: 用户发起的所有退出请求总额。
        // pendingWithdrawAmount: 已经解锁、可以随时通过 withdraw 函数取出的金额。
        
        User storage user_ = user[_pid][_user];

        for (uint256 i = 0; i < user_.requests.length; i++) {
            // 检查当前请求的解锁区块高度 (user_.requests[i].unlockBlocks) 是否小于或等于当前的区块链高度 (block.number)
            // 如果条件满足，意味着该请求的锁定期已过，这笔金额可以被取回。它被累加到 pendingWithdrawAmount 中
            if (user_.requests[i].unlockBlocks <= block.number) {
                pendingWithdrawAmount =
                    pendingWithdrawAmount +
                    user_.requests[i].amount;
            }
            requestAmount = requestAmount + user_.requests[i].amount;
        }
    }

    // ************************************** PUBLIC FUNCTION **************************************

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    // 质押合约中奖励分配的核心逻辑，它实现了懒惰结算（Lazy Accounting） 机制。
    // 它的唯一职责是计算自上次操作以来产生的奖励，并更新该池子的全局累计率 ($\mathbf{R}$ 值)，但它本身不向任何人转账
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        // getMultiplier: 计算从 lastRewardBlock 到 block.number 期间，基础奖励速率 (MetaNodePerBlock) 总共产生了多少 MetaNode
        (bool success1, uint256 totalMetaNode) = getMultiplier(
            pool_.lastRewardBlock,
            block.number
        ).tryMul(pool_.poolWeight);
        require(success1, "overflow");
        // 按权重分配: 将上述总奖励乘以该池子的权重 (pool_.poolWeight)，再除以所有池子的总权重 (totalPoolWeight)
        (success1, totalMetaNode) = totalMetaNode.tryDiv(totalPoolWeight);
        require(success1, "overflow");

        // 只有当池子中有质押代币 (stSupply > 0) 时，才进行奖励分配
        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            // 放大精度: totalMetaNode_ = totalMetaNode * 10^18 (1 ether)
            // 保证后续除法运算不会因为整数截断而损失小数部分的奖励。
            (bool success2, uint256 totalMetaNode_) = totalMetaNode.tryMul(
                1 ether
            );
            require(success2, "overflow");

            // 将放大后的总奖励除以池子总质押量 (stSupply)，得出 每 1 个 ST Token 应该获得的 MetaNode 增量
            (success2, totalMetaNode_) = totalMetaNode_.tryDiv(stSupply);
            require(success2, "overflow");

            // 将这个增量累加到 pool_.accMetaNodePerST 上，完成全局累计率的更
            (bool success3, uint256 accMetaNodePerST) = pool_
                .accMetaNodePerST
                .tryAdd(totalMetaNode_);
            require(success3, "overflow");
            pool_.accMetaNodePerST = accMetaNodePerST;
        }

        // 将 lastRewardBlock 更新为当前的 block.number。这标志着本次奖励计算的终点，也是下次奖励计算的起点
        pool_.lastRewardBlock = block.number;

        emit UpdatePool(_pid, pool_.lastRewardBlock, totalMetaNode);
    }

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /**
     * @notice Deposit staking ETH for MetaNode rewards
     */
    // 接收用户转入的 ETH，并将其添加到 ETH 质押池中进行计息
    function depositETH() public payable whenNotPaused {
        Pool storage pool_ = pool[ETH_PID];
        require(
            // 是一个双重安全检查。在 addPool 函数中，您强制要求第一个池子的质押代币地址必须是 address(0x0) (空地址)，代表 ETH 质押
            pool_.stTokenAddress == address(0x0),
            "invalid staking token address"
        );

        uint256 _amount = msg.value;
        require(
            _amount >= pool_.minDepositAmount,
            "deposit amount is too small"
        );
        // 将最终的存款任务委托给一个内部辅助函数
        _deposit(ETH_PID, _amount);
    }

    /**
     * @notice Deposit staking token for MetaNode rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their staking tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    // 允许用户将 ERC-20 代币存入指定的质押池 (_pid) 中，开始赚取 MetaNode 奖励
    function deposit(
        uint256 _pid, // 要存入的质押池 ID。
        uint256 _amount // 质押的 ERC-20 代币数量。
    ) public whenNotPaused checkPid(_pid) {
        // 强制用户不能使用这个通用的 deposit 函数来存入 ETH。根据您的合约设计，ETH 质押（PID 0）必须使用专用的 depositETH 函数
        require(_pid != 0, "deposit not support ETH staking");
        Pool storage pool_ = pool[_pid];
        require(
            // 检查存入金额 (_amount) 必须严格大于该池子设定的最小质押金额 (pool_.minDepositAmount)
            _amount > pool_.minDepositAmount,
            "deposit amount is too small"
        );

        if (_amount > 0) {
            // safeTransferFrom: 这是标准的 ERC-20 代币转账函数。它将代币从调用者 (msg.sender) 的钱包转入到当前质押合约 (address(this))
            // 前置要求: 为了让 safeTransferFrom 成功，用户必须事先对该质押合约地址调用了 ERC-20 代币的 approve 方法，授权合约可以从用户的钱包中取出至少 _amount 的代币
            IERC20(pool_.stTokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        _deposit(_pid, _amount);
    }

    /**
     * @notice Unstake staking tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of staking tokens to be withdrawn
     */
    // 发起取消质押请求
    // 该函数允许用户将他们的 ST Token 从指定的质押池中移除，同时结算他们已赚取的 MetaNode 奖励，并启动锁定期。
    // 请注意，这个函数不会实际转账 ST Token 给用户
    function unstake(
        uint256 _pid,
        uint256 _amount
    ) public whenNotPaused checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        //余额检查: 确保用户请求取消质押的金额 (_amount) 不超过他们当前的质押余额 (user_.stAmount)
        require(user_.stAmount >= _amount, "Not enough staking token balance");

        // 强制更新 全局累计率 pool_.accMetaNodePerST 到当前区块的最新值。
        updatePool(_pid);

        // 计算用户新增奖励
        uint256 pendingMetaNode_ = (user_.stAmount * pool_.accMetaNodePerST) /
            (1 ether) -
            user_.finishedMetaNode;

        if (pendingMetaNode_ > 0) {
            // 如果有新增奖励 (pendingMetaNode_ > 0)，将其累加到用户的待领取余额 (user_.pendingMetaNode) 中。这个余额需要用户调用 claim 才能转出
            user_.pendingMetaNode = user_.pendingMetaNode + pendingMetaNode_;
        }

        if (_amount > 0) {
            // 减少用户质押量: 从用户的质押余额 (user_.stAmount) 中减去请求取消质押的金额
            user_.stAmount = user_.stAmount - _amount;
            // 记录请求: 将取消质押的金额 (_amount) 和解锁区块高度记录在用户的请求数组 (user_.requests) 中
            // 解锁时间: 解锁区块= 当前区块 + 池子设定的锁定期区块数 (pool_.unstakeLockedBlocks)
            // 这正式启动了该金额的锁定期
            user_.requests.push(
                UnstakeRequest({
                    amount: _amount,
                    unlockBlocks: block.number + pool_.unstakeLockedBlocks
                })
            );
        }
        // 更新总供应量: 从池子的总质押量 (pool_.stTokenAmount) 中减去该金额，稀释度随之降低
        pool_.stTokenAmount = pool_.stTokenAmount - _amount;

        // 重置用户的奖励计算起点（快照）确保用户在未来只能基于其剩余的质押代币获取奖励
        // finishedMetaNode 存储的是用户上次与合约交互（例如，存入、取出或领取奖励）时，他的质押量和当前的全局累计率的乘积
        // 没有转账功能： finishedMetaNode 仅仅是一个存储在合约中的 uint256 数字，它从未触发 ERC-20 代币的 transfer 或 transferFrom 操作
        // 计算参照物： 它的存在是为了让合约能够通过减法来精确计算增量奖励，防止用户重复领取历史奖励
        user_.finishedMetaNode =
            (user_.stAmount * pool_.accMetaNodePerST) /
            (1 ether);

        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    /**
     * @notice Withdraw the unlock unstake amount
     *
     * @param _pid       Id of the pool to be withdrawn from
     */
    // 最终取回已解锁质押代币（ST Token 或 ETH）
    function withdraw(
        uint256 _pid
    ) public whenNotPaused checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 popNum_;
        // 遍历用户的请求列表，找出所有已解锁的请求并计算总金额
        for (uint256 i = 0; i < user_.requests.length; i++) {
            // user_.requests: 存储用户发起的所有取消质押请求，这些请求是按时间顺序（即解锁区块递增）存储的。
            // 解锁条件: if (user_.requests[i].unlockBlocks > block.number)。如果请求的解锁区块晚于当前区块，则该请求未解锁
            if (user_.requests[i].unlockBlocks > block.number) {
                break; // 遇到第一个未解锁请求，后面的请求也必然未解锁（按时间顺序存储）
            }
            // pendingWithdraw_: 累加所有已解锁请求的代币金额。
            pendingWithdraw_ = pendingWithdraw_ + user_.requests[i].amount;
            // popNum_: 记录已解锁请求的数量。
            popNum_++;
        }

        // 清理已处理的请求 (数组操作)
        // 为了高效地从动态数组中移除开头的元素（已处理的请求），合约使用了**“向前覆盖”和“删除尾部”**的方法，这比逐个删除元素更节省 Gas。
        // 步骤 A: 将未处理的请求向前移动覆盖已处理的请求
        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        // 步骤 B: 移除数组末尾被覆盖的冗余元素
        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                _safeETHTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool_.stTokenAddress).safeTransfer(
                    msg.sender,
                    pendingWithdraw_
                );
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }

    /**
     * @notice Claim MetaNode tokens reward
     *
     * @param _pid       Id of the pool to be claimed from
     */
    // 用户领取 MetaNode 奖励的核心入口点，它负责结算所有应得的奖励，将奖励代币转账给用户，并重置奖励计算起点
    function claim(
        uint256 _pid
    ) public whenNotPaused checkPid(_pid) whenNotClaimPaused {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        // pendingMetaNode_ 现在存储的是用户当前可以立即领取的全部 MetaNode 奖励总额
        uint256 pendingMetaNode_ = (user_.stAmount * pool_.accMetaNodePerST) /
            (1 ether) -
            user_.finishedMetaNode +
            user_.pendingMetaNode;

        // 转账检查: 只有当总可领金额大于零时才执行转账。
        if (pendingMetaNode_ > 0) {
            // 清理待领余额: 将用户的存储变量 user_.pendingMetaNode 清零。由于金额已准备转账，此余额不再需要存储在合约中。
            user_.pendingMetaNode = 0;
            // 转账: 调用内部辅助函数 _safeMetaNodeTransfer，将总奖励代币 (pendingMetaNode_) 从合约地址转账到用户的钱包 (msg.sender)
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }

        // 重置奖励快照 (MasterChef 核心)
        // 目的: 这是防止重复领取的关键。在奖励转账完成后，用户的奖励计算起点 (finishedMetaNode) 必须被重置到最新状态。
        // 用户下次调用 claim 时，计算将从这个新的、更高的值开始，确保只结算从本次转账后新赚取的奖励。
        user_.finishedMetaNode =
            (user_.stAmount * pool_.accMetaNodePerST) /
            (1 ether);

        emit Claim(msg.sender, _pid, pendingMetaNode_);
    }

    // ************************************** INTERNAL FUNCTION **************************************

    /**
     * @notice Deposit staking token for MetaNode rewards
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of staking tokens to be deposited
     */
    // 执行存款的核心逻辑，它封装了奖励结算和所有状态更新步骤

    function _deposit(uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        // 关键第一步。在修改任何状态之前，强制更新 全局累计率pool_.accMetaNodePerST 到当前区块的最新值。这确保了所有现有质押者都能公平地结算到本次操作前的奖励。
        updatePool(_pid);

        // 用户在该池子中已经有质押代币,则必须结算他们自上次操作以来赚取的奖励。
        if (user_.stAmount > 0) {
            // uint256 accST = user_.stAmount.mulDiv(pool_.accMetaNodePerST, 1 ether);
            // 计算用户当前的总理论收益 (Current Theoretical Reward)
            (bool success1, uint256 accST) = user_.stAmount.tryMul(
                pool_.accMetaNodePerST
            );
            require(success1, "user stAmount mul accMetaNodePerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");

            // 计算新增收益 = 当前总理论收益 - 上次快照起点
            (bool success2, uint256 pendingMetaNode_) = accST.trySub(
                user_.finishedMetaNode
            );
            require(success2, "accST sub finishedMetaNode overflow");

            if (pendingMetaNode_ > 0) {
                // 将新增收益累加到用户的待领取余额中
                (bool success3, uint256 _pendingMetaNode) = user_
                    .pendingMetaNode
                    .tryAdd(pendingMetaNode_);
                require(success3, "user pendingMetaNode overflow");
                user_.pendingMetaNode = _pendingMetaNode;
            }
        }

        // 更新用户质押量
        if (_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }
        // 更新池子总质押量
        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(
            _amount
        );
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        // user_.finishedMetaNode = user_.stAmount.mulDiv(pool_.accMetaNodePerST, 1 ether);
        // 重置奖励快照
        (bool success6, uint256 finishedMetaNode) = user_.stAmount.tryMul(
            pool_.accMetaNodePerST
        );
        require(success6, "user stAmount mul accMetaNodePerST overflow");

        (success6, finishedMetaNode) = finishedMetaNode.tryDiv(1 ether);
        require(success6, "finishedMetaNode div 1 ether overflow");

        user_.finishedMetaNode = finishedMetaNode;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice Safe MetaNode transfer function, just in case if rounding error causes pool to not have enough MetaNodes
     *
     * @param _to        Address to get transferred MetaNodes
     * @param _amount    Amount of MetaNode to be transferred
     */
    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        // 合约计算出的用户应得奖励 (_amount) 是一个理论值。
        // 然而，如果奖励代币的发行方（Minter/Owner）没有及时将足够的 MetaNode 充值到质押合约中，那么合约的余额可能会低于用户应得的总额。
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));

        if (_amount > MetaNodeBal) {
            MetaNode.transfer(_to, MetaNodeBal);
        } else {
            MetaNode.transfer(_to, _amount);
        }
    }

    /**
     * @notice Safe ETH transfer function
     *
     * @param _to        Address to get transferred ETH
     * @param _amount    Amount of ETH to be transferred
     */
    // 安全地将以太币 (ETH) 从合约转账给用户
    // 是在 Solidity 中向外部地址发送 ETH 的推荐方式（优于 transfer 和 send，因为它转发了所有剩余的 Gas）
    // 在 Solidity 0.5.0 版本之前，transfer 是发送 ETH 的标准方式。它只转发 2300 Gas。设计者认为这足以覆盖外部账户接收 ETH 的开销
    // 后来发现这是一个严重的安全缺陷，被称为 Gas Limit 陷阱 (Gas Limit Attack)：
    // 目标是合约：如果接收 ETH 的目标地址是一个智能合约，并且这个合约的 receive() 或 fallback() 函数在执行时需要的 Gas 超过 2300（例如，它需要执行一些存储或逻辑操作），那么 transfer 就会因为 Gas 不足而失败 (revert)。
    // 不可预测性：随着 EVM 升级和操作码 Gas 成本的变化，原本够用的 2300 Gas 可能变得不够用，导致旧合约的功能意外中断。
    function _safeETHTransfer(address _to, uint256 _amount) internal {
        (bool success, bytes memory data) = address(_to).call{value: _amount}(
            ""
        );

        require(success, "ETH transfer call failed");
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "ETH transfer operation did not succeed"
            );
        }
    }
}
