
const { ethers }  = require("hardhat");

async function main() {
    console.log("========================================");
    console.log("开始部署 SHIB风格Meme代币合约");
    console.log("========================================\n");
    // deploer
    const [deployer] = await ethers.getSigners();
    console.log("📍 部署账户:", deployer.address);


    // balance
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 账户余额:", ethers.formatEther(balance), "ETH\n");


    //     console.log("📦 部署 Mock Router...");
    // // 部署模拟的Uniswap V2 Router
    // const UniswapV2Factory = await ethers.getContractFactory("UniswapV2FactoryMock");
    // const factory = await UniswapV2Factory.deploy();
        
    // const UniswapV2Router = await ethers.getContractFactory("UniswapV2Router02Mock");
    // const router = await UniswapV2Router.deploy(await factory.getAddress()); 
    // const mockRouterAddress = await router.getAddress();



    // config
    const config={
        name:"shib meme",
        symbol:"ShibMM",
        totalSupply: ethers.parseEther("1000000000000"), // 1万亿代币,

        // Uniswap V2 Router地址
        // Ethereum Mainnet: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        // Sepolia Testnet: 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008
        routerAddress: process.env.UNISWAP_ROUTER || "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008",
        // routerAddress:mockRouterAddress,
        marketingAddress: process.env.MARKETING_WALLET || deployer.address,
        devAddress: process.env.DEV_WALLET || deployer.address

    };
       console.log("📋 部署配置:");
    console.log("   代币名称:", config.name);
    console.log("   代币符号:", config.symbol);
    console.log("   总供应量:", ethers.formatEther(config.totalSupply));
    console.log("   Router地址:", config.routerAddress);
    console.log("   营销钱包:", config.marketingAddress);
    console.log("   开发钱包:", config.devAddress);
    console.log();


    // =============deploy==========
    console.log("🚀 开始部署合约...\n");







    const shibMemeToken = await ethers.getContractFactory("shibMeme");
    console.log("合约工厂创建成功");
    

    const token = await shibMemeToken.deploy(
        config.name,
        config.symbol,
        config.totalSupply,
        config.routerAddress,
        config.marketingAddress,
        config.devAddress,
        {
            gasLimit: 8000000
        }
    
    );
    console.log("部署交易已发送:");
    await token.waitForDeployment();
    
    const tokenAddress = await token.getAddress();
    console.log("✅ 合约部署成功!");
    console.log("📍 合约地址:", tokenAddress);
    console.log();


    const pairAddress = await token.uniswapV2Pair();
    console.log("🔗 Uniswap交易对地址:", pairAddress);
    console.log();


    const [buytax,selltax] = await token.getTaxRates();
    console.log("buytax",buytax.toString(),"基点 (", (Number(buytax) / 100).toFixed(2), "%)");
    console.log("selltax",selltax.toString(),"基点 (", (Number(selltax) / 100).toFixed(2), "%)");
    

    const [maxTx, maxWalletAmount, coolDownTime] = await token.getLimits();
    console.log("   最大交易额:", ethers.formatEther(maxTx), "代币");
    console.log("   最大持有量:", ethers.formatEther(maxWalletAmount), "代币");
    console.log("   冷却期:", coolDownTime.toString(), "秒");

    const ownerBalance = await token.balanceOf(deployer.address);
    console.log("   Owner余额:", ethers.formatEther(ownerBalance), "代币");

    // =========================================
    const JSONbig = require('json-bigint')({ useNativeBigInt: true });
    const deploymentInfo={
        network: (await ethers.provider.getNetwork()).name,
        chainId: (await ethers.provider.getNetwork()).chainId,
        deployer:deployer.address,
        timestamp: new Date().toISOString(),
        contracts:{
            token:tokenAddress,
            pair:pairAddress
        },
        config:{
           name:config.name,
           symbol:config.symbol,
           totalSupply: config.totalSupply.toString(),
           routerAddress:config.routerAddress,
           marketingAddress:config.marketingAddress,
           devAddress:config.devAddress 
        },
        initialSettings: {
            buyTax: buytax.toString(),
            sellTax: selltax.toString(),
            maxTxAmount: maxTx.toString(),
            maxWalletAmount: maxWalletAmount.toString(),
            cooldownPeriod: coolDownTime.toString()
        }

    };

    const fs = require("fs");
    const path = require("path");

    const deploymentsDir = path.join(__dirname, "..", "deployments");
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir);
    };
    const filename = `deployment-${Date.now()}.json`;
    const filepath = path.join(deploymentsDir, filename);

    fs.writeFileSync(filepath, JSONbig.stringify(deploymentInfo, null, 2));
    

    console.log("💾 部署信息已保存至:", filepath);
    console.log();
    console.log("========================================");
    console.log("✨ 部署完成!");
    console.log("========================================");


}
main().then(() => process.exit(0)).catch(
    (error) => {
        console.error("\n❌ 部署失败:");
        console.error(error);
        process.exit(1);
    }
);