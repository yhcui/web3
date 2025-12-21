// 部署 MetaNodeStake
module.exports = async ({ethers, getNamedAccounts, deployments, upgrades}) => {
    // 1、获取部署账户
    const {deployer} = await getNamedAccounts();
    // console.log("deployer: ", deployer);

    // 2、部署 MetaNode Token 合约
    const metaNodeToken = await deployments.deploy("MetaNodeToken", {from: deployer, args: [], log: false});
    // console.log("MetaNodeToken deployed to:", metaNodeToken.address);

    // 3、部署 MetaNodeStake 合约
    const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");

    //  部署获取到的MetaNode Token 地址
    const MetaNodeToken = metaNodeToken.address;
    // 质押起始区块高度,可以去sepolia上面读取最新的区块高度
    const blockNumber = await ethers.provider.getBlockNumber();
    // console.log("当前 blockNumber 号:", blockNumber);
    const startBlock = blockNumber + 100;
    // console.log("当前 startBlock 区块号:", startBlock);
    // 质押结束的区块高度,sepolia 出块时间是12s,想要质押合约运行x秒,那么endBlock = startBlock+x/12
    const endBlock = blockNumber + 10000; //
    // console.log("当前 endBlock 区块号:", endBlock);
    // 每个区块奖励的MetaNode token的数量
    const MetaNodePerBlock = "20000000000000000";

    const metaNodeStake = await upgrades.deployProxy(MetaNodeStake, [MetaNodeToken, startBlock, endBlock, MetaNodePerBlock], {
        initializer: "initialize"
    });
    await metaNodeStake.waitForDeployment();
    const metaNodeStakeAddress = await metaNodeStake.getAddress();
    const metaNodeStakeImplAddress = await upgrades.erc1967.getImplementationAddress(metaNodeStakeAddress);
    // console.log("MetaNodeStake deployed to:", metaNodeStakeAddress);
    // console.log("MetaNodeStake Impl deployed to:", metaNodeStakeImplAddress);

    // 4、保存部署信息
    await deployments.save("MetaNodeStake", {
        address: metaNodeStakeAddress,
        implementation: metaNodeStakeImplAddress,
        abi: metaNodeStake.interface.format("json"),
        // 关键点：把自定义数据放在 linkedData 里
        linkedData: {
            startBlock: startBlock,
            endBlock: endBlock
        }
    });
    // console.log("MetaNodeStake deployment info saved.");
};

module.exports.tags = ["MetaNodeStake"];
