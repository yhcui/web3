// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
（二）实践操作
合约开发：基于以太坊或其他主流区块链平台，使用 Solidity 或其他智能合约开发语言，实现一个 SHIB 风格的 Meme 代币合约。合约需包含以下功能：
代币税功能：实现交易税机制，对每笔代币交易征收一定比例的税费，并将税费分配给特定的地址或用于特定的用途。
流动性池集成：设计并实现与流动性池的交互功能，支持用户向流动性池添加和移除流动性。
交易限制功能：设置合理的交易限制，如单笔交易最大额度、每日交易次数限制等，防止恶意操纵市场。
*/

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IGovernanceHandler} from "../interfaces/IGovernanceHandler.sol";
import {ITreasuryHandler} from "../interfaces/ITreasuryHandler.sol";
import {ITaxHandler} from "../interfaces/ITexHandler.sol";

contract MyMeme is ERC20, Ownable {
    /// @notice 治理相关地址
    address public governanceHandler;

    /// @notice 税费相关地址
    address public texHandler;

    /// @notice 税费接收地址
    address public lpReceiver;

    /// @notice 金库接收地址
    address public treasuryReceiver;

    /**
     * @notice 构造函数
     * @param owner 合约所有者地址
     * @param governanceHandler_ 治理处理器地址
     * @param texHandler_ 税费处理器地址
     * @param lpReceiver_ 税费接收地址
     * @param treasuryReceiver_ 金库接收地址
     */
    constructor(
        address owner,
        address governanceHandler_,
        address texHandler_,
        address lpReceiver_,
        address treasuryReceiver_
    ) ERC20("MyMeme", "HMEME") Ownable(owner) {
        // 设置治理处理器
        governanceHandler = governanceHandler_;
        // 设置税费处理器
        texHandler = texHandler_;
        // 设置税费接收地址
        lpReceiver = lpReceiver_;
        // 设置金库接收地址
        treasuryReceiver = treasuryReceiver_;
    }

    /**
     * @notice 管理员挖矿
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice 设置治理处理器地址
     */
    function setGovernanceHandler(address addr) public onlyOwner {
        governanceHandler = addr;
    }

    /**
     * @notice 设置税费处理器地址
     */
    function setTexHandler(address addr) public onlyOwner {
        texHandler = addr;
    }

    /**
     * @notice 设置 LP 接收地址
     */
    function setLpReceiver(address addr) public onlyOwner {
        lpReceiver = addr;
    }

    /**
     * @notice 设置金库接收地址
     */
    function setTreasuryReceiver(address addr) public onlyOwner {
        treasuryReceiver = addr;
    }

    /**
     * @notice 重写交易，增加代币税
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // 调用金库处理器的转账前操作
        ITreasuryHandler(treasuryReceiver).beforeTransferHandler(
            from,
            to,
            amount
        );

        // 计算税费
        (
            uint256 transferAmount,
            uint256 lpAmount,
            uint256 reflectAmount,
            uint256 treasuryAmount,
            uint256 burnAmount
        ) = ITaxHandler(texHandler).getTax(from, to, amount);

        // 扣除总税费后转账给接收方
        super._update(from, to, transferAmount);
        IGovernanceHandler(governanceHandler).move_delegate(
            from,
            to,
            uint224(transferAmount)
        );

        // 分配税费
        if (lpAmount > 0) {
            super._update(from, lpReceiver, lpAmount);
            IGovernanceHandler(governanceHandler).move_delegate(
                from,
                lpReceiver,
                uint224(transferAmount)
            );
        }
        if (reflectAmount > 0) {
            super._update(from, address(this), reflectAmount);
            IGovernanceHandler(governanceHandler).move_delegate(
                from,
                address(this),
                uint224(transferAmount)
            );
        }
        if (treasuryAmount > 0) {
            super._update(from, treasuryReceiver, treasuryAmount);
            IGovernanceHandler(governanceHandler).move_delegate(
                from,
                treasuryReceiver,
                uint224(transferAmount)
            );
        }
        if (burnAmount > 0) {
            super._update(from, address(0), burnAmount);
            IGovernanceHandler(governanceHandler).move_delegate(
                from,
                address(0),
                uint224(transferAmount)
            );
        }

        // 调用金库处理器的转账后操作
        ITreasuryHandler(treasuryReceiver).afterTransferHandler(
            from,
            to,
            amount
        );
    }

    /**
     * @notice 获取反射分红
     */
    function claimReflection() public {
        uint256 contractBalance = balanceOf(address(this));
        require(contractBalance > 0, "No reflections available");

        // 按持币比例分配反射分红
        uint256 totalSupply_ = totalSupply();
        uint256 holderBalance = balanceOf(msg.sender);
        uint256 reward = (contractBalance * holderBalance) /
            (totalSupply_ - contractBalance);

        require(reward > 0, "No reflection for holder");

        super._transfer(address(this), msg.sender, reward);
    }

    /**
     * @notice 委托投票权
     * @param to 被委托的代表地址
     */
    function delegate(address to) external {
        uint256 amount = balanceOf(msg.sender);
        IGovernanceHandler(governanceHandler).delegate(msg.sender, to, amount);
    }

    /**
     * @notice 通过签名委托投票权
     * @param to 代表人地址
     * @param nonce 签名的随机数
     * @param expiry 签名的过期时间
     * @param v 签名的v值
     * @param r 签名的r值
     * @param s 签名的s值
     */
    function delegateBySig(
        address to,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        address from = IGovernanceHandler(governanceHandler).checkBySig(
            to,
            nonce,
            expiry,
            v,
            r,
            s
        );
        uint256 amount = balanceOf(from);
        IGovernanceHandler(governanceHandler).delegate(from, to, amount);
    }

    /**
     * @notice 获取指定账户在指定区块的投票数
     * @param account 要查询的账户地址
     * @param blockNumber 要查询的区块号
     */
    function getVotesAtBlock(
        address account,
        uint32 blockNumber
    ) public view returns (uint224) {
        return
            IGovernanceHandler(governanceHandler).getVotesAtBlock(
                account,
                blockNumber
            );
    }
}
