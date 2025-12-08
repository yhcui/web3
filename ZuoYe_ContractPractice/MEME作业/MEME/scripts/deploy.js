const hre = require("hardhat");

async function main() {
    console.log("开始部署 ShibaMemeCoin 合约...");

    // 获取部署者账户
    const [deployer] = await hre.ethers.getSigners();
    console.log("部署账户:", deployer.address);
    console.log("账户余额:", hre.ethers.utils.formatEther(await deployer.getBalance()));

    // 合约参数配置
    const MARKETING_WALLET = "0x742d35Cc6634C0532925a3b8D76Cc05d6Bc7Ab"; // 替换为实际营销钱包地址
    const LIQUIDITY_WALLET = "0xdD2FD4581271e230360230F9337D5c0430Bf44C0"; // 替换为实际流动性钱包地址

    // Uniswap V2 Router 地址 (主网和测试网)
    const ROUTER_ADDRESSES = {
        mainnet: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        goerli: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        sepolia: "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008",
        polygon: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
        bsc: "0x10ED43C718714eb63d5aA57B78B54704E256024E"
    };

    const networkName = hre.network.name;
    console.log("当前网络:", networkName);

    let routerAddress;
    if (networkName === "localhost" || networkName === "hardhat") {
        // 本地测试网络，需要部署模拟路由
        console.log("检测到本地网络，将部署模拟路由合约...");

        // 部署 WETH 模拟合约
        const WETH = await hre.ethers.getContractFactory("WETH9");
        const weth = await WETH.deploy();
        await weth.deployed();
        console.log("WETH 部署到:", weth.address);

        // 部署 UniswapV2Factory
        const Factory = await hre.ethers.getContractFactory("UniswapV2Factory");
        const factory = await Factory.deploy(deployer.address);
        await factory.deployed();
        console.log("UniswapV2Factory 部署到:", factory.address);

        // 部署 UniswapV2Router02
        const Router = await hre.ethers.getContractFactory("UniswapV2Router02");
        const router = await Router.deploy(factory.address, weth.address);
        await router.deployed();
        console.log("UniswapV2Router02 部署到:", router.address);

        routerAddress = router.address;
    } else {
        routerAddress = ROUTER_ADDRESSES[networkName];
        if (!routerAddress) {
            throw new Error(`不支持的网络: ${networkName}`);
        }
    }

    console.log("使用路由地址:", routerAddress);

    // 部署 ShibaMemeCoin 合约
    const ShibaMemeCoin = await hre.ethers.getContractFactory("ShibaMemeCoin");
    const shibaMemeCoin = await ShibaMemeCoin.deploy(
        MARKETING_WALLET,
        LIQUIDITY_WALLET,
        routerAddress
    );

    await shibaMemeCoin.deployed();

    console.log("ShibaMemeCoin 部署成功!");
    console.log("合约地址:", shibaMemeCoin.address);

    // 获取合约信息
    const tokenInfo = await shibaMemeCoin.getTokenInfo();
    console.log("\n=== 代币信息 ===");
    console.log("名称:", await shibaMemeCoin.name());
    console.log("符号:", await shibaMemeCoin.symbol());
    console.log("精度:", await shibaMemeCoin.decimals());
    console.log("总供应量:", hre.ethers.utils.formatEther(tokenInfo.totalSupply_));
    console.log("流通供应量:", hre.ethers.utils.formatEther(tokenInfo.circulatingSupply));

    // 获取费用信息
    const feeInfo = await shibaMemeCoin.getFeeInfo();
    console.log("\n=== 费用配置 ===");
    console.log("买入税:", feeInfo.buyTax / 100, "%");
    console.log("卖出税:", feeInfo.sellTax / 100, "%");
    console.log("转账税:", feeInfo.transferTax / 100, "%");
    console.log("流动性费用:", feeInfo.liquidityFee / 100, "%");
    console.log("反射费用:", feeInfo.reflectionFee / 100, "%");
    console.log("销毁费用:", feeInfo.burnFee / 100, "%");
    console.log("营销费用:", feeInfo.marketingFee / 100, "%");

    // 获取限制信息
    const limitInfo = await shibaMemeCoin.getLimitInfo();
    console.log("\n=== 交易限制 ===");
    console.log("最大交易量:", hre.ethers.utils.formatEther(limitInfo.maxTransactionAmount));
    console.log("最大持有量:", hre.ethers.utils.formatEther(limitInfo.maxWalletAmount));
    console.log("交易间隔:", limitInfo.minTimeBetweenTx, "秒");
    console.log("限制是否生效:", limitInfo.limitsInEffect);

    console.log("\n=== 重要地址 ===");
    console.log("营销钱包:", await shibaMemeCoin.marketingWallet());
    console.log("流动性钱包:", await shibaMemeCoin.liquidityWallet());
    console.log("Uniswap V2 Pair:", await shibaMemeCoin.uniswapV2Pair());

    // 保存部署信息到文件
    const deploymentInfo = {
        network: networkName,
        timestamp: new Date().toISOString(),
        contractAddress: shibaMemeCoin.address,
        deployerAddress: deployer.address,
        marketingWallet: MARKETING_WALLET,
        liquidityWallet: LIQUIDITY_WALLET,
        routerAddress: routerAddress,
        pairAddress: await shibaMemeCoin.uniswapV2Pair(),
        tokenInfo: {
            name: await shibaMemeCoin.name(),
            symbol: await shibaMemeCoin.symbol(),
            decimals: await shibaMemeCoin.decimals(),
            totalSupply: tokenInfo.totalSupply_.toString()
        },
        feeInfo: {
            buyTax: feeInfo.buyTax,
            sellTax: feeInfo.sellTax,
            transferTax: feeInfo.transferTax,
            liquidityFee: feeInfo.liquidityFee,
            reflectionFee: feeInfo.reflectionFee,
            burnFee: feeInfo.burnFee,
            marketingFee: feeInfo.marketingFee
        },
        limitInfo: {
            maxTransactionAmount: limitInfo.maxTransactionAmount.toString(),
            maxWalletAmount: limitInfo.maxWalletAmount.toString(),
            minTimeBetweenTx: limitInfo.minTimeBetweenTx,
            limitsInEffect: limitInfo.limitsInEffect
        }
    };

    const fs = require('fs');
    fs.writeFileSync(
        './deployments/deployment-info.json',
        JSON.stringify(deploymentInfo, null, 2)
    );

    console.log("\n✅ 部署完成! 部署信息已保存到 ./deployments/deployment-info.json");

    // 如果在测试网或主网上，提示验证合约
    if (networkName !== "localhost" && networkName !== "hardhat") {
        console.log("\n📝 合约验证命令:");
        console.log(`npx hardhat verify --network ${networkName} ${shibaMemeCoin.address} "${MARKETING_WALLET}" "${LIQUIDITY_WALLET}" "${routerAddress}"`);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("部署失败:", error);
        process.exit(1);
    });