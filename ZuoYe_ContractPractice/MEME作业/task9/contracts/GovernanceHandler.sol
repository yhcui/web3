// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernanceHandler} from "../interfaces/IGovernanceHandler.sol";

contract GovernanceHandler is IGovernanceHandler, Ownable {
    /// @notice Registry of user delegates for governance.
    mapping(address => address) public delegates;
    /// @notice Registry of the number of balance checkpoints an account has.
    mapping(address => uint32) public numCheckpoints;
    /// @notice Registry of balance checkpoints per account.
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The EIP-712 typehash for the contract's domain.
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );
    /// @notice The EIP-712 typehash for the delegation struct used by the contract.
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    /// @notice Registry of nonces for vote delegation.
    mapping(address => uint256) public nonces;

    constructor(address owner) Ownable(owner) {}

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
    ) external onlyOwner returns (address) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("MyMeme")),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, to, nonce, expiry)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address from = ecrecover(digest, v, r, s);

        require(
            from != address(0),
            "FLOKI:delegateBySig:INVALID_SIGNATURE: Received signature was invalid."
        );
        require(
            block.timestamp <= expiry,
            "FLOKI:delegateBySig:EXPIRED_SIGNATURE: Received signature has expired."
        );
        require(
            nonce == nonces[from]++,
            "FLOKI:delegateBySig:INVALID_NONCE: Received nonce was invalid."
        );

        return from;
    }

    /**
     * @notice 委托投票权
     * @param from 委托人地址
     * @param to 代表人地址
     * @param amount 要委托的投票数
     */
    function delegate(
        address from,
        address to,
        uint256 amount
    ) public onlyOwner {
        address cur = delegates[from];
        delegates[from] = to;

        move_delegate_raw(cur, to, uint224(amount));
        emit DelegateChanged(from, cur, to);
    }

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
    ) public onlyOwner {
        if (from == to) {
            return;
        }
        if (amount == 0) {
            return;
        }

        if (from != address(0)) {
            uint32 fromRepNum = numCheckpoints[from];
            uint224 fromRepOld = fromRepNum > 0
                ? checkpoints[from][fromRepNum - 1].votes
                : 0;
            uint224 fromRepNew = fromRepOld - amount;

            _writeCheckpoint(from, fromRepNum, fromRepOld, fromRepNew);
        }

        if (to != address(0)) {
            uint32 toRepNum = numCheckpoints[to];
            uint224 toRepOld = toRepNum > 0
                ? checkpoints[to][toRepNum - 1].votes
                : 0;
            uint224 toRepNew = toRepOld + amount;

            _writeCheckpoint(to, toRepNum, toRepOld, toRepNew);
        }
    }

    /**
     * @notice 转移代表的投票数
     * @param from 投票数转出的代表地址
     * @param to 投票数转入的代表地址
     * @param amount 要转移的投票数
     */
    function move_delegate(
        address from,
        address to,
        uint256 amount
    ) public onlyOwner {
        move_delegate_raw(delegates[from], delegates[to], uint224(amount));
    }

    /**
     * @notice 记录账户的投票检查点
     * @param account 要记录检查点的账户地址
     * @param nCheckpoints 该账户当前的检查点数量
     * @param oldVotes 该账户的旧投票数
     * @param newVotes 该账户的新投票数
     */
    function _writeCheckpoint(
        address account,
        uint32 nCheckpoints,
        uint224 oldVotes,
        uint224 newVotes
    ) private {
        uint32 blockNumber = uint32(block.number);

        // 同一区块只需一条记录
        if (
            nCheckpoints > 0 &&
            checkpoints[account][nCheckpoints - 1].blockNumber == blockNumber
        ) {
            checkpoints[account][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[account][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[account] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(account, oldVotes, newVotes);
    }

    /**
     * @notice 获取指定账户在指定区块的投票数
     * @param account 要查询的账户地址
     * @param blockNumber 要查询的区块号
     * @return 指定账户在指定区块的投票数
     */
    function getVotesAtBlock(
        address account,
        uint32 blockNumber
    ) external view onlyOwner returns (uint224) {
        require(
            blockNumber < block.number,
            "FLOKI:getVotesAtBlock:FUTURE_BLOCK: Cannot get votes at a block in the future."
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance.
        if (checkpoints[account][nCheckpoints - 1].blockNumber <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance.
        if (checkpoints[account][0].blockNumber > blockNumber) {
            return 0;
        }

        // Perform binary search.
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
}
