// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 * @title Governance token interface.
 * 投票权与区块号紧密关联，这是去中心化自治组织（DAO）和链上治理机制设计中的一个核心安全和公平性措施，通常被称为投票快照（Voting Snapshot）
 * 区块链上的投票权通常与用户持有的治理代币数量挂钩（例如，持有 100 个代币就有 100 票）。为了确保投票过程的公平性，系统需要在投票开始时冻结每个人的投票权重。这个“冻结”操作就是通过区块号实现的
 * 如果没有快照，就会出现以下问题：瞬时投票（Flash Voting）: 恶意用户可以利用闪电贷（Flash Loan）在一笔交易中借入大量的治理代币
 * 投票期内转移: 如果投票权与当前余额挂钩，用户可以在投票期内出售代币，但其投票仍然有效；或者购买代币只是为了投票，投完后立即出售。快照确保了：只有在快照时拥有代币的人才有投票权，且其投票权重在整个投票期内固定不变
 * 确保一致性和可验证性。区块号是区块链上最客观、不可篡改的时间戳和状态标识符
 * 避免投票前的抢跑 (Front-Running)。设定一个未来的或临近的区块作为快照点，可以避免代币持有者在提案发布后，为了获得更大投票权而进行的代币抢购（套利）行为，从而保证了投票启动时的公平性。
 * 
 * 在实际的 DAO 治理系统中，通常会采取以下两种机制中的一种，来缓解您提到的这种“买入-投票-卖出”的套利行为：
 * 1. 延时快照（Past Block Snapshot）这是最主流的解决方案，即快照点必须是提案创建时间之前的某个区块。如何运作？
 * 治理合约通常规定，当有人提出一个新提案时，快照区块 (blockNumber) 必须是：快照区块> 当前区块 - N 其中 N 是一个较大的区块数（例如，提案创建前 10,000 个区块，或以时间计量的 2 天前）。
 * 目的和效果消除时间套利窗口: 提案人不能选择一个“临近”的区块。他们必须选择一个过去的、且满足延迟要求的区块作为快照点。
 * 无法提前买入: 由于提案创建时，快照区块的状态早已确定，用户在知道有提案要发起时，无法通过即时买入代币来影响已经过去的快照点的投票权重。
 * 确定性: 保证了投票权重是基于代币持有者在提案发布前的真实、稳定的分布。
 * 
 * 软约束和经济激励（针对实时快照）
 * 如果您看到的系统确实允许使用临近区块（或当前区块）作为快照点，那么系统往往依赖于经济学和时间成本来阻止大规模的买入-投票-卖出套利。
 * A. 交易成本和滑点
 * 购入和卖出大量代币会产生显著的交易费用（Gas Fee）和市场滑点（Slippage）。
 * 如果投票提案带来的潜在经济收益（例如，改变协议参数带来的利润）小于购买和卖出代币的总交易成本，这种套利行为就无利可图。
 * B. 市场深度和价格影响
 *  对于流动性一般的治理代币，恶意用户如果想在短时间内大量买入以获得决定性投票权，会急剧推高代币价格。
 * 当投票结束后，他们试图抛售这些代币时，又会遭受巨大的价格冲击（导致低价卖出），从而使“买高卖低”的净损失大于投票带来的潜在收益。
 * 
 */
interface IGovernanceToken {
    /// @notice A checkpoint for marking number of votes as of a given block.
    // 该结构体用于记录某个地址在特定区块时的投票余额
    struct Checkpoint {
        // The 32-bit unsigned integer is valid until these estimated dates for these given chains:
        //  - BSC: Sat Dec 23 2428 18:23:11 UTC
        //  - ETH: Tue Apr 18 3826 09:27:12 UTC
        // This assumes that block mining rates don't speed up.
        // 记录投票余额的区块号
        uint32 blockNumber;
        // This type is set to `uint224` for optimizations purposes (i.e., specifically to fit in a 32-byte block). It
        // assumes that the number of votes for the implementing governance token never exceeds the maximum value for a
        // 224-bit number.
        // 该区块时账户所拥有的投票数量
        //使用 uint224 也是为了存储优化（使 Checkpoint 结构体正好占用一个 32 字节的存储槽）
        uint224 votes;
    }

    /**
     * @notice Determine the number of votes for an account as of a block number.
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check.
     * @param blockNumber The block number to get the vote balance at.
     * @return The number of votes the account had as of the given block.
     */
    // 查询一个地址在历史某个区块拥有多少投票余额的核心函数
    function getVotesAtBlock(address account, uint32 blockNumber) external view returns (uint224);

    /// @notice Emitted whenever a new delegate is set for an account.
    // 当一个账户（delegator，委托人）将其投票权委托给另一个地址时触发
    event DelegateChanged(address delegator, address currentDelegate, address newDelegate);

    /// @notice Emitted when a delegate's vote count changes.
    // 当一个被委托人（delegatee）的总投票余额发生变化时触发。这通常发生在：
    // 1、有人将投票权委托给或取消委托于该 delegatee。
    // 2、delegatee 自己购买、出售或转账了代币。
    event DelegateVotesChanged(address delegatee, uint224 oldVotes, uint224 newVotes);
}