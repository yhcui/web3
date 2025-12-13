const { ethers }  = require("hardhat");

async function main() {
    const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;

    const [signer] = await ethers.getSigners();
    console.log("📍 操作账户:", signer.address);
    console.log("📍 合约地址:", TOKEN_ADDRESS);
    console.log();

    const token =await  ethers.getContractAt("shibMeme",TOKEN_ADDRESS);

    console.log("name:",await token.name());
    console.log("symbol:",await token.symbol());
    console.log("totalSupply:",ethers.formatEther(await token.totalSupply()));
    console.log("balance:",ethers.formatEther(await token.balanceOf(signer.address)));


    const [buyTax, sellTax] = await token.getTaxRates();
    console.log("buyTax:",buyTax.toString());
    console.log("sellTax:",sellTax.toString());


    const [liq, mark, dev, burn] = await token.getTaxDistribution();
    console.log("   流动性份额:", (Number(liq) / 100).toFixed(2) + "%");
    console.log("   营销份额:", (Number(mark) / 100).toFixed(2) + "%");
    console.log("   开发份额:", (Number(dev) / 100).toFixed(2) + "%");
    console.log("   销毁份额:", (Number(burn) / 100).toFixed(2) + "%");
    console.log();
    
    // ============ 查询交易限制 ============
    
    console.log("🚦 交易限制:");
    const [maxTx, maxWallet, cooldown] = await token.getLimits();
    console.log("   限制启用:", await token.isLimitEnable());
    console.log("   最大交易额:", ethers.formatEther(maxTx));
    console.log("   最大持有量:", ethers.formatEther(maxWallet));
    console.log("   冷却期:", cooldown.toString(), "秒");
    console.log();
    
    // ============ 查询交易状态 ============
    
    console.log("🔄 交易状态:");
    console.log("   交易已启用:", await token.tradingEnabled());
    const tradingTime = await token.tradingEnabledTimestamp();
    if (tradingTime > 0) {
        console.log("   启用时间:", new Date(Number(tradingTime) * 1000).toLocaleString());
    }
    console.log();
    
    // ============ 查询Uniswap信息 ============
    
    console.log("🔗 Uniswap信息:");
    console.log("   Router地址:", await token.uniswapV2Router());
    console.log("   交易对地址:", await token.uniswapV2Pair());
    console.log("   自动流动性启用:", await token.swapAndLiquifyEnabled());
    console.log("   Swap阈值:", ethers.formatEther(await token.swapThreshold()));
    console.log("   待处理税费:", ethers.formatEther(await token.getPendingTaxTokens()));


// ============ 管理功能示例 ============
    
    console.log("========================================");
    console.log("🛠️  管理功能示例 (取消注释以执行):");
    console.log("========================================\n");
    
    // 修改税率
    console.log("// 修改税率为 买入3% / 卖出8%");
    await token.setTaxRates(300, 800);
    console.log();
    
    // 修改税费分配
    console.log("// 修改税费分配为 流动性50% / 营销30% / 开发10% / 销毁10%");
    await token.setTaxDistribution(5000, 3000, 1000, 1000);
    console.log();
    
    // 调整交易限制
    console.log("// 调整最大交易额为总供应量的1%");
    const newMaxTx = (await token.totalSupply()) * 10n / 1000n;
    const newMaxWallet = (await token.totalSupply()) * 30n / 1000n;
    await token.setLimits(newMaxTx, newMaxWallet);
    console.log();
    
    //设置免税地址
    console.log("// 设置某地址免税");
    const exemptAddress = '0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199';
    await token.setExcludedFromFees(exemptAddress, true);
    console.log();
    
    // 添加黑名单
    console.log("// 添加地址到黑名单");
    const blacklistAddress = '0xdD2FD4581271e230360230F9337D5c0430Bf44C0';
     await token.setBlackAddress(blacklistAddress, true);
    console.log();
    
    // 启用交易
    console.log("// 启用交易（只能执行一次）");
    await token.enableTrading();
    console.log();
    
    // 禁用交易限制
    console.log("// 禁用交易限制（通常在项目成熟后）");
    await token.setLimitEnable(false);
    console.log();
    
    
    
    // 更新税费钱包
    console.log("// 更新税费接收钱包");
    const newLiqWallet = '0x042e30d946f82044de1bc3e63af7f9be03848065';
    const newMarkWallet = '0x042e30d946f82044de1bc3e63af7f9be03848065';
    const newDevWallet = '0x042e30d946f82044de1bc3e63af7f9be03848065';
    await token.setTaxwallet(newLiqWallet, newMarkWallet, newDevWallet);
    console.log();
    
    // 示例10：调整冷却期
    console.log("// 调整冷却期为30秒");
    await token.setCooldownTime(30);
    console.log();
    
    console.log("========================================");
    console.log("✨ 查询完成!");
    console.log("========================================");





    




}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n❌ 执行失败:");
        console.error(error);
        process.exit(1);
    });

