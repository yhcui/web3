const hre = require("hardhat");

async function main() {
    console.log("开始与 ShibaMemeCoin 合约交互...");

    // 读取部署信息
    const fs = require('fs');
    let deploymentInfo;
    try {
        deploymentInfo = JSON.parse(fs.readFileSync('./deployments/deployment-info.json', 'utf8'));
    } catch (error) {
        console.error("无法读取部署信息，请先运行部署脚本");
        process.exit(1);
    }

    // 获取合约实例
    const ShibaMemeCoin = await hre.ethers.getContractFactory("ShibaMemeCoin");
    const contract = await ShibaMemeCoin.attach(deploymentInfo.contractAddress);

    const [owner, user1, user2] = await hre.ethers.getSigners();

    console.log("合约地址:", contract.address);
    console.log("所有者地址:", owner.address);
    console.log("用户1地址:", user1.address);
    console.log("用户2地址:", user2.address);

    try {
        // 1. 查看初始状态
        console.log("\n=== 1. 初始状态查看 ===");
        const tokenInfo = await contract.getTokenInfo();
        console.log("总供应量:", hre.ethers.utils.formatEther(tokenInfo.totalSupply_));
        console.log("流通供应量:", hre.ethers.utils.formatEther(tokenInfo.circulatingSupply));
        console.log("合约余额:", hre.ethers.utils.formatEther(tokenInfo.contractBalance));
        console.log("交易是否启用:", tokenInfo.tradingEnabled_);

        console.log("\n所有者余额:", hre.ethers.utils.formatEther(await contract.balanceOf(owner.address)));

        // 2. 启用交易
        console.log("\n=== 2. 启用交易 ===");
        const enableTx = await contract.enableTrading(true);
        await enableTx.wait();
        console.log("✅ 交易已启用");

        // 3. 转账测试（免费转账）
        console.log("\n=== 3. 免费转账测试 ===");
        const transferAmount = hre.ethers.utils.parseEther("1000000"); // 100万代币

        // 先将用户1设置为免费
        const excludeTx = await contract.excludeFromFees(user1.address, true);
        await excludeTx.wait();
        console.log("✅ 用户1已免除费用");

        const transferTx = await contract.transfer(user1.address, transferAmount);
        await transferTx.wait();
        console.log("✅ 转账成功");

        console.log("用户1余额:", hre.ethers.utils.formatEther(await contract.balanceOf(user1.address)));

        // 4. 收费转账测试
        console.log("\n=== 4. 收费转账测试 ===");

        // 取消用户1的费用豁免
        const includeTx = await contract.excludeFromFees(user1.address, false);
        await includeTx.wait();
        console.log("✅ 用户1费用豁免已取消");

        const taxTransferAmount = hre.ethers.utils.parseEther("10000"); // 1万代币
        const beforeBalance = await contract.balanceOf(user2.address);
        const beforeContractBalance = await contract.balanceOf(contract.address);

        const taxTransferTx = await contract.connect(user1).transfer(user2.address, taxTransferAmount);
        await taxTransferTx.wait();
        console.log("✅ 收费转账完成");

        const afterBalance = await contract.balanceOf(user2.address);
        const afterContractBalance = await contract.balanceOf(contract.address);

        console.log("用户2转账前余额:", hre.ethers.utils.formatEther(beforeBalance));
        console.log("用户2转账后余额:", hre.ethers.utils.formatEther(afterBalance));
        console.log("实际收到:", hre.ethers.utils.formatEther(afterBalance.sub(beforeBalance)));
        console.log("合约转账前余额:", hre.ethers.utils.formatEther(beforeContractBalance));
        console.log("合约转账后余额:", hre.ethers.utils.formatEther(afterContractBalance));
        console.log("税费收入:", hre.ethers.utils.formatEther(afterContractBalance.sub(beforeContractBalance)));

        // 5. 更新税费配置测试
        console.log("\n=== 5. 税费配置更新测试 ===");
        const newTaxRates = {
            buyTax: 300,        // 3%
            sellTax: 600,       // 6%
            transferTax: 100,   // 1%
            liquidityFee: 200,  // 2%
            reflectionFee: 200, // 2%
            burnFee: 100,       // 1%
            marketingFee: 300   // 3%
        };

        const updateTaxTx = await contract.updateTaxRates(newTaxRates);
        await updateTaxTx.wait();
        console.log("✅ 税费配置已更新");

        const updatedFeeInfo = await contract.getFeeInfo();
        console.log("新的买入税:", updatedFeeInfo.buyTax / 100, "%");
        console.log("新的卖出税:", updatedFeeInfo.sellTax / 100, "%");

        // 6. 交易限制测试
        console.log("\n=== 6. 交易限制测试 ===");
        const newLimits = {
            maxTransactionAmount: hre.ethers.utils.parseEther("50000"), // 5万代币
            maxWalletAmount: hre.ethers.utils.parseEther("100000"),      // 10万代币
            minTimeBetweenTx: 60, // 60秒
            limitsInEffect: true
        };

        const updateLimitsTx = await contract.updateTradingLimits(newLimits);
        await updateLimitsTx.wait();
        console.log("✅ 交易限制已更新");

        const updatedLimitInfo = await contract.getLimitInfo();
        console.log("新的最大交易量:", hre.ethers.utils.formatEther(updatedLimitInfo.maxTransactionAmount));
        console.log("新的最大持有量:", hre.ethers.utils.formatEther(updatedLimitInfo.maxWalletAmount));

        // 7. 黑名单功能测试
        console.log("\n=== 7. 黑名单功能测试 ===");

        // 将用户2加入黑名单
        const blacklistTx = await contract.blacklist(user2.address, true);
        await blacklistTx.wait();
        console.log("✅ 用户2已加入黑名单");

        // 尝试从黑名单用户转账（应该失败）
        try {
            const blacklistTransferTx = await contract.connect(user2).transfer(user1.address, hre.ethers.utils.parseEther("1000"));
            await blacklistTransferTx.wait();
            console.log("❌ 黑名单限制失效");
        } catch (error) {
            console.log("✅ 黑名单限制正常工作，转账被拒绝");
        }

        // 移除黑名单
        const unblacklistTx = await contract.blacklist(user2.address, false);
        await unblacklistTx.wait();
        console.log("✅ 用户2已从黑名单移除");

        // 8. 查看最终状态
        console.log("\n=== 8. 最终状态 ===");
        const finalTokenInfo = await contract.getTokenInfo();
        console.log("总供应量:", hre.ethers.utils.formatEther(finalTokenInfo.totalSupply_));
        console.log("流通供应量:", hre.ethers.utils.formatEther(finalTokenInfo.circulatingSupply));
        console.log("合约余额:", hre.ethers.utils.formatEther(finalTokenInfo.contractBalance));
        console.log("已销毁代币:", hre.ethers.utils.formatEther(finalTokenInfo.burnedTokens));

        console.log("\n各用户余额:");
        console.log("所有者:", hre.ethers.utils.formatEther(await contract.balanceOf(owner.address)));
        console.log("用户1:", hre.ethers.utils.formatEther(await contract.balanceOf(user1.address)));
        console.log("用户2:", hre.ethers.utils.formatEther(await contract.balanceOf(user2.address)));

        console.log("\n✅ 所有测试完成!");

    } catch (error) {
        console.error("交互过程中出错:", error);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("交互失败:", error);
        process.exit(1);
    });