// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Governance token interface.
 */
interface IGovernanceHandler {
    /// @notice A checkpoint for marking number of votes as of a given block.
    struct Checkpoint {
        // The 32-bit unsigned integer is valid until these estimated dates for these given chains:
        //  - BSC: Sat Dec 23 2428 18:23:11 UTC
        //  - ETH: Tue Apr 18 3826 09:27:12 UTC
        // This assumes that block mining rates don't speed up.
        uint32 blockNumber;
        // This type is set to `uint224` for optimizations purposes (i.e., specifically to fit in a 32-byte block). It
        // assumes that the number of votes for the implementing governance token never exceeds the maximum value for a
        // 224-bit number.
        uint224 votes;
    }

    /// @notice 当委托人更改其代表时触发。
    event DelegateChanged(
        address delegator,
        address currentDelegate,
        address newDelegate
    );

    /// @notice 当代表的投票数发生变化时触发。
    event DelegateVotesChanged(
        address delegatee,
        uint224 oldVotes,
        uint224 newVotes
    );

    /**
     * @notice 验证签名并返回签名者地址
     * @param to 代表人地址
     * @param nonce 签名的随机数
     * @param expiry 签名的过期时间
     * @param v 签名的v值
     * @param r 签名的r值
     * @param s 签名的s值
     * @return 签名者地址
     */
    function checkBySig(
        address to,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (address);

    /**
     * @notice 委托投票权
     * @param from 委托人地址
     * @param to 代表人地址
     * @param amount 要委托的投票数
     */
    function delegate(address from, address to, uint256 amount) external;

    /**
     * @notice 转移代表的投票数
     * @param from 投票数转出的代表地址
     * @param to 投票数转入的代表地址
     * @param amount 要转移的投票数
     */
    function move_delegate_raw(
        address from,
        address to,
        uint224 amount
    ) external;

    /**
     * @notice 转移代表的投票数
     * @param from 投票数转出的代表地址
     * @param to 投票数转入的代表地址
     * @param amount 要转移的投票数
     */
    function move_delegate(address from, address to, uint256 amount) external;

    /**
     * @notice 获取指定账户在指定区块的投票数
     * @param account 要查询的账户地址
     * @param blockNumber 要查询的区块号
     * @return 指定账户在指定区块的投票数
     */
    function getVotesAtBlock(
        address account,
        uint32 blockNumber
    ) external view returns (uint224);
}
