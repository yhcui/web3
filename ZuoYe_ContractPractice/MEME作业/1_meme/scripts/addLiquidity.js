const { ethers }  = require("hardhat");

async function main() {


    const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;
    const ROUTER_ADDRESS = process.env.ROUTER_ADDRESS || "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008";

    const TOKEN_AMOUNT = ethers.parseEther("500000000000")
    const ETH_AMOUNT = ethers.parseEther("0.0001")

    const [signer] = await ethers.getSigners();
    console.log("📍 操作账户:", signer.address);
    console.log();



    const token =await  ethers.getContractAt("shibMeme",TOKEN_ADDRESS);

    const routerABI = [
        "function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)",
        "function factory() external view returns (address)",
        "function WETH() external view returns (address)"
    ];
    const router = new ethers.Contract(ROUTER_ADDRESS,routerABI,signer);

    console.log("📋 配置信息:");
    console.log("   代币地址:", TOKEN_ADDRESS);
    console.log("   Router地址:", ROUTER_ADDRESS);
    console.log("   添加代币数量:", ethers.formatEther(TOKEN_AMOUNT));
    console.log("   添加ETH数量:", ethers.formatEther(ETH_AMOUNT));
    console.log();

    const tokenBalance = await token.balanceOf(signer.address);
    const ethBalance = await ethers.provider.getBalance(signer.address);

    console.log("💰 账户余额:");
    console.log("   代币:", ethers.formatEther(tokenBalance));
    console.log("   ETH:", ethers.formatEther(ethBalance));
    console.log();

    if (tokenBalance < TOKEN_AMOUNT) {
        console.error("❌ 代币余额不足!");
        return;
    }
    
    if (ethBalance < ETH_AMOUNT) {
        console.error("❌ ETH余额不足!");
        return;
    }

    console.log("🔐 授权Router使用代币...");
    const approveTx = await token.approve(ROUTER_ADDRESS,TOKEN_AMOUNT);
    await approveTx.wait();
    console.log("✅ 授权完成\n");


    const deadline = Math.floor(Date.now()/1000)+60*20;

    const addLiquidityTx=await router.addLiquidityETH(
        TOKEN_ADDRESS,
        TOKEN_AMOUNT,
        0,
        0,
        signer.address,
        deadline,
        {value:ETH_AMOUNT}

    );


    const receipt = await addLiquidityTx.wait();

    console.log("add hex",receipt.hash);

    const pairAddress = await token.uniswapV2Pair();
    console.log("🔗 交易对地址:", pairAddress);
    console.log();


    // 方法2: 通过 Factory 获取（推荐）
    console.log("🔄 通过 Factory 获取 LP Token 地址...");
    const factoryAddress = await router.factory();
    const wethAddress = await router.WETH();
    
    const factoryABI = [
        "function getPair(address tokenA, address tokenB) external view returns (address pair)"
    ];
    const factory = new ethers.Contract(factoryAddress, factoryABI, signer);
    
    const lpTokenAddress = await factory.getPair(TOKEN_ADDRESS, wethAddress);
    console.log("🔗 LP Token 地址 (通过 Factory):", lpTokenAddress);
    console.log();

    // 检查 LP Token 余额
    const pairABI = [
        "function balanceOf(address) view returns (uint256)",
        "function totalSupply() view returns (uint256)",
        "function token0() external view returns (address)",
        "function token1() external view returns (address)"
    ];
    
    const lpToken = new ethers.Contract(lpTokenAddress, pairABI, signer);
    const lpBalance = await lpToken.balanceOf(signer.address);
    const totalSupply = await lpToken.totalSupply();
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    console.log("📊 LP Token 信息:");
    console.log("   LP 余额:", ethers.formatEther(lpBalance));
    console.log("   总供应量:", ethers.formatEther(totalSupply));
    console.log("   Token0:", token0);
    console.log("   Token1:", token1);
    console.log();

    // 最终余额检查
    const finalTokenBalance = await token.balanceOf(signer.address);
    const finalEthBalance = await ethers.provider.getBalance(signer.address);

    console.log("💰 最终账户余额:");
    console.log("   代币:", ethers.formatEther(finalTokenBalance));
    console.log("   ETH:", ethers.formatEther(finalEthBalance));
    console.log("   LP Token:", ethers.formatEther(lpBalance));
    console.log();

    console.log("🎉 流动性添加完成!");
    console.log("💡 重要: 保存你的 LP Token 地址:", lpTokenAddress);




    




    
}


main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n❌ 执行失败:");
        console.error(error);
        process.exit(1);
    });