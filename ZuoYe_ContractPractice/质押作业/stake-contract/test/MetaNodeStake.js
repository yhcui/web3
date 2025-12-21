const {ethers, deployments, upgrades} = require("hardhat");
const {expect} = require("chai");
const {time} = require("@nomicfoundation/hardhat-network-helpers");

describe("MetaNodeStake test ===========================================================", function () {
    let deployer, user1, user2;
    let deploy_info;

    let stake_ins1;
    let stake_ins2;
    let stake_ins2_user1;

    let ADMIN_ROLE;
    let UPGRADE_ROLE;

    let erc20;
    let erc20Ins;

    // 所有测试用例执行前执行
    before(async function () {
        // 获取账户
        [deployer, user1, user2] = await ethers.getSigners();
    });

    it("-------------------------------------------------- contract simple deploy and init", async function () {
        console.log("      -------------------------------------------------- contract simple deploy and init");
        // 使用 ethers 部署 MetaNodeToken 合约
        const MetaNodeToken = await ethers.getContractFactory("MetaNodeToken");
        const token_ins = await MetaNodeToken.deploy();
        console.log("          MetaNodeToken deployed to:", token_ins.target);
        expect(token_ins.target).to.properAddress;

        // 使用 ethers 部署 MetaNodeStake 合约
        const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake2");
        const stake_ins = await MetaNodeStake.deploy();
        console.log("          MetaNodeStake deployed to:", stake_ins.target);
        expect(stake_ins.target).to.properAddress;

        // 初始化合约
        await expect(stake_ins.initialize(token_ins.target, 3000n, 2000n, 10000000000000000n)).to.be.revertedWith("invalid parameters");
        await stake_ins.initialize(token_ins.target, 1000n, 2000n, 10000000000000000n);
        await expect(stake_ins.initialize(token_ins.target, 1000n, 2000n, 10000000000000000n)).to.be.revertedWithCustomError(stake_ins, "InvalidInitialization");
        const startBlock = await stake_ins.startBlock();
        expect(startBlock).to.equal(1000n);
        const endBlock = await stake_ins.endBlock();
        expect(endBlock).to.equal(2000n);
        const rewardPerBlock = await stake_ins.MetaNodePerBlock();
        expect(rewardPerBlock).to.equal(10000000000000000n);
    });

    it("-------------------------------------------------- contract uups deploy and upgrade", async function () {
        console.log("      -------------------------------------------------- contract uups deploy");

        // 部署 MetaNodeStake 合约
        await deployments.fixture(["MetaNodeStake"]);
        deploy_info = await deployments.get("MetaNodeStake");
        console.log("          MetaNodeStake deployed to:", deploy_info.address);
        console.log("          MetaNodeStake Impl deployed to:", deploy_info.implementation);
        console.log("          startBlock:", deploy_info.linkedData.startBlock);
        console.log("          endBlock:", deploy_info.linkedData.endBlock);

        // 获取合约实例
        stake_ins1 = await ethers.getContractAt("MetaNodeStake", deploy_info.address);
        const version1 = await stake_ins1.version();
        expect(version1).to.equal("v1.0.0");

        // 获取管理员角色
        ADMIN_ROLE = await stake_ins1.ADMIN_ROLE();
        UPGRADE_ROLE = await stake_ins1.UPGRADE_ROLE();

        // 获取 MetaNodeStake2 合约工厂
        const MetaNodeStakeV2 = await ethers.getContractFactory("MetaNodeStake2");
        // 升级合约 - 测试非管理员升级合约失败
        await expect(upgrades.upgradeProxy(deploy_info.address, MetaNodeStakeV2.connect(user1)))
            .to.be.revertedWithCustomError(stake_ins1, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, UPGRADE_ROLE);

        // 升级合约 - 成功升级
        stake_ins2 = await upgrades.upgradeProxy(deploy_info.address, MetaNodeStakeV2);
        await stake_ins2.waitForDeployment();
        const version2 = await stake_ins2.version();
        expect(version2).to.equal("v2.0.0");

        // 获取合约实例 - user1
        stake_ins2_user1 = stake_ins2.connect(user1);
        // 获取管理员角色
        ADMIN_ROLE = await stake_ins1.ADMIN_ROLE();
        UPGRADE_ROLE = await stake_ins1.UPGRADE_ROLE();
    });

    it("-------------------------------------------------- admin function - ", async function () {
        console.log("      -------------------------------------------------- admin function - ");
        // 部署新的质押代币合约
        const MetaNodeToken = await ethers.getContractFactory("MetaNodeToken");
        const token_ins = await MetaNodeToken.deploy();
        console.log("          MetaNodeToken2 deployed to:", token_ins.target);

        // 修改质押代币
        const tokenAddress1 = await stake_ins2.MetaNode();
        await expect(stake_ins2_user1.setMetaNode(token_ins.target)).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await stake_ins2.setMetaNode(token_ins.target);
        const tokenAddress2 = await stake_ins2.MetaNode();
        expect(tokenAddress1).to.not.equal(tokenAddress2);

        // 修改质押起始区块高度
        const startBlock1 = await stake_ins2.startBlock();
        await expect(stake_ins2_user1.setStartBlock(startBlock1 + 100n))
            .to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.setStartBlock(startBlock1 + 200000n)).to.be.revertedWith("start block must be smaller than end block");
        await stake_ins2.setStartBlock(startBlock1 + 100n);
        const startBlock2 = await stake_ins2.startBlock();
        expect(startBlock2).to.equal(startBlock1 + 100n);

        // 修改质押结束区块高度
        const endBlock1 = await stake_ins2.endBlock();
        await expect(stake_ins2_user1.setEndBlock(endBlock1 - 100n))
            .to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.setEndBlock(10n)).to.be.revertedWith("start block must be smaller than end block");
        await stake_ins2.setEndBlock(endBlock1 - 100n);
        const endBlock2 = await stake_ins2.endBlock();
        expect(endBlock2).to.equal(endBlock1 - 100n);

        // 修改每个区块奖励的质押代币数量
        const rewardPerBlock1 = await stake_ins2.MetaNodePerBlock();
        await expect(stake_ins2_user1.setMetaNodePerBlock(60000000000000000n)).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.setMetaNodePerBlock(0)).to.be.revertedWith("invalid parameter");
        await stake_ins2.setMetaNodePerBlock(50000000000000000n);
        const rewardPerBlock2 = await stake_ins2.MetaNodePerBlock();
        expect(rewardPerBlock1).to.not.equal(rewardPerBlock2);
    });

    it("-------------------------------------------------- pool function", async function () {
        console.log("      -------------------------------------------------- pool function");

        // 部署一个新的 ERC20 代币用于质押测试
        const MetaERC20 = await ethers.getContractFactory("MetaERC20");
        erc20 = await MetaERC20.deploy();
        console.log("          MetaERC20 Token deployed to:", erc20.target);

        // 添加无效质押池 - 已经结束
        const blockNumber = await ethers.provider.getBlockNumber();
        await stake_ins2.setStartBlock(blockNumber);
        await stake_ins2.setEndBlock(blockNumber + 1);
        await timeover(10);
        await expect(stake_ins2.addPool(ethers.ZeroAddress, 20n, ethers.parseUnits("0.001", 18), 800n, false)).to.be.revertedWith("Already ended");
        await stake_ins2.setEndBlock(blockNumber + 10000);

        // 添加 ETH 质押池
        await expect(stake_ins2_user1.addPool(ethers.ZeroAddress, 20n, ethers.parseUnits("0.001", 18), 800n, false))
            .to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.addPool(erc20.target, 20n, ethers.parseUnits("0.001", 18), 800n, false)).to.be.revertedWith("invalid staking token address");
        await expect(stake_ins2.addPool(ethers.ZeroAddress, 20n, ethers.parseUnits("0.001", 18), 0, true)).to.be.revertedWith("invalid withdraw locked blocks");
        await stake_ins2.addPool(ethers.ZeroAddress, 10n, ethers.parseUnits("0.001", 18), 800n, true);
        await expect(stake_ins2.addPool(ethers.ZeroAddress, 10n, ethers.parseUnits("0.001", 18), 800n, false)).to.be.revertedWith("invalid staking token address");
        const poolLength2 = await stake_ins2.poolLength();
        expect(poolLength2).to.equal(1n);

        // 添加 ERC20 质押池
        await stake_ins2.addPool(erc20.target, 20n, ethers.parseUnits("0.001", 18), 800n, true);
        await stake_ins2.addPool(erc20.target, 20n, ethers.parseUnits("0.001", 18), 800n, false);
        const poolLength3 = await stake_ins2.poolLength();
        expect(poolLength3).to.equal(3n);

        // 更新质押池
        await expect(stake_ins2_user1.updatePool(100, ethers.parseUnits("0.01", 18), 900n))
            .to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount")
            .withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.updatePool(100, ethers.parseUnits("0.01", 18), 900n)).to.be.revertedWith("invalid pid");
        await stake_ins2.updatePool(0, ethers.parseUnits("0.01", 18), 900n);
        let pool0 = await stake_ins2.pool(0);
        expect(pool0.minDepositAmount).to.equal(ethers.parseUnits("0.01", 18));

        // 测试 setPoolWeight
        await expect(stake_ins2_user1.setPoolWeight(0, 50n, true)).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await expect(stake_ins2.setPoolWeight(0, 0, true)).to.be.revertedWith("invalid pool weight");
        await stake_ins2.setPoolWeight(0, 50n, true);
        await stake_ins2.setPoolWeight(0, 50n, false);
        pool0 = await stake_ins2.pool(0);
        expect(pool0.poolWeight).to.equal(50n);
    });

    it("-------------------------------------------------- before deposit function", async function () {
        console.log("      -------------------------------------------------- before deposit function");

        // 验证无效质押池的质押奖励
        await expect(stake_ins2_user1.pendingMetaNode(100, user1.address)).to.be.revertedWith("invalid pid");

        // 验证用户 user1 ETH 的质押奖励
        const reword1 = await stake_ins2_user1.pendingMetaNode(0, user1.address);
        console.log("          用户 user1 ETH 的质押奖励:", reword1 / 10n ** 18n);
        expect(reword1).to.be.eq(0n);

        // 验证用户 user1 ERC20 的质押奖励
        const reword2 = await stake_ins2_user1.pendingMetaNode(1, user1.address);
        console.log("          用户 user1 ERC20 的质押奖励:", reword2 / 10n ** 18n);
        expect(reword2).to.be.eq(0n);

        const blockNumber = await ethers.provider.getBlockNumber();

        // 验证无效质押池的质押奖励
        await expect(stake_ins2_user1.pendingMetaNodeByBlockNumber(100, user1.address, blockNumber)).to.be.revertedWith("invalid pid");

        // 验证用户 user1 ETH 的质押奖励
        const reword3 = await stake_ins2_user1.pendingMetaNodeByBlockNumber(0, user1.address, blockNumber);
        console.log("          用户 user1 ETH 的质押奖励2:", reword3 / 10n ** 18n);
        expect(reword3).to.be.eq(0n);

        // 验证用户 user1 ERC20 的质押奖励
        const reword4 = await stake_ins2_user1.pendingMetaNodeByBlockNumber(1, user1.address, blockNumber);
        console.log("          用户 user1 ERC20 的质押奖励2:", reword4 / 10n ** 18n);
        expect(reword4).to.be.eq(0n);

        // 更新所有质押池状态
        await stake_ins2.massUpdatePools();
        await expect(stake_ins2.updatePool(100)).to.be.revertedWith("invalid pid");
        await stake_ins2.updatePool(0);

        console.log("------------------------------------------------ 获取奖励");
        // 获取奖励
        await expect(stake_ins2_user1.claim(100)).to.be.revertedWith("invalid pid");
        await stake_ins2_user1.claim(0);
        await stake_ins2_user1.claim(1);
        console.log("------------------------------------------------ 获取奖励完成");

        console.log("------------------------------------------------ 取出质押");
        // 取出质押
        await expect(stake_ins2_user1.withdraw(100)).to.be.revertedWith("invalid pid");
        await stake_ins2_user1.withdraw(0);
        await stake_ins2_user1.withdraw(1);
        console.log("------------------------------------------------ 取出质押完成");

        // 取消质押
        await expect(stake_ins2_user1.unstake(100, 0)).to.be.revertedWith("invalid pid");
        await stake_ins2_user1.unstake(0, 0);
        await stake_ins2_user1.unstake(1, 0);
        await expect(stake_ins2_user1.unstake(0, 100)).to.be.revertedWith("Not enough staking token balance");
        await expect(stake_ins2_user1.unstake(1, 100)).to.be.revertedWith("Not enough staking token balance");
    });

    it("-------------------------------------------------- deposit funciton", async function () {
        console.log("      -------------------------------------------------- deposit funciton");
        // 给用户 user1 转账一些 ETH 和 ERC20 代币用于质押测试
        erc20Ins = await ethers.getContractAt("MetaERC20", erc20.target);
        await deployer.sendTransaction({
            to: user1.address,
            value: ethers.parseEther("200.0")
        });
        await erc20Ins.transfer(user1.address, ethers.parseUnits("200", 18));

        // 验证无效质押池的质押余额
        await expect(stake_ins2_user1.stakingBalance(100, user1.address)).to.be.revertedWith("invalid pid");

        // 用户 user1 质押 ETH 到池子并验证质押余额
        await expect(stake_ins2_user1.depositETH({value: ethers.parseEther("0.0000000000001")})).to.be.revertedWith("deposit amount is too small");
        await stake_ins2_user1.depositETH({value: ethers.parseEther("50")});
        await stake_ins2_user1.depositETH({value: ethers.parseEther("50")});
        expect(await stake_ins2_user1.stakingBalance(0, user1.address)).to.equal(ethers.parseEther("100"));

        // 用户 user1 质押 ERC20 到池子并验证质押余额 - 在 Ethers v6 中，Contract 不再有 .address 属性，取地址应使用 await contract.getAddress()（或直接用 contract.target）。
        await erc20Ins.connect(user1).approve(stake_ins2.target, ethers.parseUnits("200", 18));
        await expect(stake_ins2_user1.deposit(100, ethers.parseUnits("50", 18))).to.be.revertedWith("invalid pid");
        await expect(stake_ins2_user1.deposit(0, ethers.parseUnits("50", 18))).to.be.revertedWith("deposit not support ETH staking");
        await expect(stake_ins2_user1.deposit(1, ethers.parseUnits("0.0000000000001", 18))).to.be.revertedWith("deposit amount is too small");
        await stake_ins2_user1.deposit(1, ethers.parseUnits("50", 18));
        await stake_ins2_user1.deposit(1, ethers.parseUnits("50", 18));
        expect(await stake_ins2_user1.stakingBalance(1, user1.address)).to.equal(ethers.parseUnits("100", 18));

        // 验证用户 user1 ETH 的质押奖励
        let reword1 = await stake_ins2_user1.pendingMetaNode(0, user1.address);
        expect(reword1).to.be.gt(0n);
        // 验证用户 user1 ERC20 的质押奖励
        let reword2 = await stake_ins2_user1.pendingMetaNode(1, user1.address);
        expect(reword2).to.be.gt(0n);

        await timeover(600);
        await stake_ins2_user1.depositETH({value: ethers.parseEther("50")});
        await stake_ins2_user1.deposit(1, ethers.parseUnits("50", 18));

        // 时间跃迁，模拟质押一段时间后，用户获取质押奖励
        await timeover(600);

        // 验证无效质押池的质押奖励
        await expect(stake_ins2_user1.pendingMetaNode(100, user1.address)).to.be.revertedWith("invalid pid");
        // 验证用户 user1 ETH 的质押奖励
        reword1 = await stake_ins2_user1.pendingMetaNode(0, user1.address);
        console.log("          用户 user1 ETH 的质押奖励:", reword1 / 10n ** 18n);
        expect(reword1).to.be.gt(0n);

        // 验证用户 user1 ERC20 的质押奖励
        reword2 = await stake_ins2_user1.pendingMetaNode(1, user1.address);
        console.log("          用户 user1 ERC20 的质押奖励:", reword2 / 10n ** 18n);
        expect(reword2).to.be.gt(0n);

        // 无效的取回申请
        await expect(stake_ins2_user1.withdrawAmount(100, user1.address)).to.be.revertedWith("invalid pid");

        // 获取当前赎回金额 user1 withdrawAmount ETH
        const [requestAmount1, pendingWithdrawAmount1] = await stake_ins2_user1.withdrawAmount(0, user1.address);
        console.log("          用户 user1 的 ETH 申请赎回金额:", requestAmount1 / 10n ** 18n);
        console.log("          用户 user1 的 ETH 可以赎回金额:", pendingWithdrawAmount1 / 10n ** 18n);

        // 获取当前赎回金额 user1 withdrawAmount ERC20
        const [requestAmount2, pendingWithdrawAmount2] = await stake_ins2_user1.withdrawAmount(1, user1.address);
        console.log("          用户 user1 的 ETH 申请赎回金额:", requestAmount2 / 10n ** 18n);
        console.log("          用户 user1 的 ETH 可以赎回金额:", pendingWithdrawAmount2 / 10n ** 18n);

        // 用户 user1 提交赎回申请
        await expect(stake_ins2_user1.unstake(0, 0)).to.be.emit(stake_ins2_user1, "RequestUnstake");
        await expect(stake_ins2_user1.unstake(0, ethers.parseEther("100000"))).to.be.revertedWith("Not enough staking token balance");
        await stake_ins2_user1.unstake(0, ethers.parseEther("10"));
        const [requestAmount3, pendingWithdrawAmount3] = await stake_ins2_user1.withdrawAmount(0, user1.address);
        console.log("          用户 user1 的 ETH 申请赎回金额:", requestAmount3 / 10n ** 18n);
        console.log("          用户 user1 的 ETH 可以赎回金额:", pendingWithdrawAmount3 / 10n ** 18n);
        expect(requestAmount3).to.equal(requestAmount1 + ethers.parseEther("10"));

        // 用户 user1 提交赎回申请 ERC20
        await expect(stake_ins2_user1.unstake(1, 0)).to.be.emit(stake_ins2_user1, "RequestUnstake");
        await expect(stake_ins2_user1.unstake(1, ethers.parseUnits("100000", 18))).to.be.revertedWith("Not enough staking token balance");
        await stake_ins2_user1.unstake(1, ethers.parseUnits("20", 18));
        const [requestAmount4, pendingWithdrawAmount4] = await stake_ins2_user1.withdrawAmount(1, user1.address);
        console.log("          用户 user1 的 ERC20 申请赎回金额:", requestAmount4 / 10n ** 18n);
        console.log("          用户 user1 的 ERC20 可以赎回金额:", pendingWithdrawAmount4 / 10n ** 18n);
        expect(requestAmount4).to.equal(requestAmount2 + ethers.parseUnits("20", 18));

        // 时间跃迁，模拟质押一段时间后，用户获取质押奖励
        await timeover(1000);

        // 再次获取当前赎回金额 user1 withdrawAmount ETH
        const [requestAmount5, pendingWithdrawAmount5] = await stake_ins2_user1.withdrawAmount(0, user1.address);
        console.log("          用户 user1 的申请赎回金额:", requestAmount5 / 10n ** 18n);
        console.log("          用户 user1 的可以赎回金额:", pendingWithdrawAmount5 / 10n ** 18n);

        // 获取当前赎回金额 user1 withdrawAmount ERC20
        const [requestAmount6, pendingWithdrawAmount6] = await stake_ins2_user1.withdrawAmount(1, user1.address);
        console.log("          用户 user1 的 ERC20 申请赎回金额:", requestAmount6 / 10n ** 18n);
        console.log("          用户 user1 的 ERC20 可以赎回金额:", pendingWithdrawAmount6 / 10n ** 18n);

        // 停止领取奖励和取出质押
        await expect(stake_ins2_user1.pauseClaim()).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await stake_ins2.pauseClaim();
        await expect(stake_ins2.pauseClaim()).to.be.revertedWith("claim has been already paused");
        await expect(stake_ins2_user1.pauseWithdraw()).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await stake_ins2.pauseWithdraw();
        await expect(stake_ins2.pauseWithdraw()).to.be.revertedWith("withdraw has been already paused");

        await expect(stake_ins2_user1.claim(0)).to.be.revertedWith("claim is paused");
        await expect(stake_ins2_user1.claim(1)).to.be.revertedWith("claim is paused");

        // 恢复领取奖励和取出质押
        await expect(stake_ins2_user1.unpauseClaim()).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await stake_ins2.unpauseClaim();
        await expect(stake_ins2.unpauseClaim()).to.be.revertedWith("claim has been already unpaused");
        await expect(stake_ins2_user1.unpauseWithdraw()).to.be.revertedWithCustomError(stake_ins2, "AccessControlUnauthorizedAccount").withArgs(user1.address, ADMIN_ROLE);
        await stake_ins2.unpauseWithdraw();
        await expect(stake_ins2.unpauseWithdraw()).to.be.revertedWith("withdraw has been already unpaused");

        console.log("------------------------------------------------ 获取奖励");
        // 获取奖励
        await stake_ins2_user1.claim(0);
        await stake_ins2_user1.claim(1);
        console.log("------------------------------------------------ 获取奖励完成");

        console.log("------------------------------------------------ 取出质押");
        // 取出质押
        await stake_ins2_user1.withdraw(0);
        await stake_ins2_user1.withdraw(1);
        console.log("------------------------------------------------ 取出质押完成");

        // 再次获取当前赎回金额 user1 withdrawAmount ETH
        const [requestAmount7, pendingWithdrawAmount7] = await stake_ins2_user1.withdrawAmount(0, user1.address);
        console.log("          用户 user1 的申请赎回金额:", requestAmount7 / 10n ** 18n);
        console.log("          用户 user1 的可以赎回金额:", pendingWithdrawAmount7 / 10n ** 18n);

        // 获取当前赎回金额 user1 withdrawAmount ERC20
        const [requestAmount8, pendingWithdrawAmount8] = await stake_ins2_user1.withdrawAmount(1, user1.address);
        console.log("          用户 user1 的 ERC20 申请赎回金额:", requestAmount8 / 10n ** 18n);
        console.log("          用户 user1 的 ERC20 可以赎回金额:", pendingWithdrawAmount8 / 10n ** 18n);
    });

    it("getMultiplier 边界测试", async () => {
        const startBlock = await stake_ins2.startBlock();
        const endBlock = await stake_ins2.endBlock();
        await expect(stake_ins2.getMultiplier(startBlock + 1000n, startBlock + 500n)).to.be.revertedWith("invalid block");
        await expect(stake_ins2.getMultiplier(0, endBlock - 10n)).to.not.be.reverted;
        await expect(stake_ins2.getMultiplier(startBlock + 10n, endBlock + 10n)).to.not.be.reverted;
        await expect(stake_ins2.getMultiplier(0, startBlock - 10n)).to.be.revertedWith("end block must be greater than start block");
    });
});

async function timeover(n) {
    const newBlockNumber1 = await ethers.provider.getBlockNumber();
    console.log("              时间跃迁开始 :", newBlockNumber1);

    // 推进 10 个区块
    for (let i = 0; i < n; i++) {
        await ethers.provider.send("evm_mine");
    }

    const newBlockNumber2 = await ethers.provider.getBlockNumber();
    console.log("              时间跃迁结束 :", newBlockNumber2);
}
