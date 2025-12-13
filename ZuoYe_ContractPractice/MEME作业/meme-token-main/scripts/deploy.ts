import { network } from "hardhat";

const { ethers } = await network.connect({
  network: "sepolia",
  chainType: "l1",
});
import FactoryArtifact  from '@uniswap/v2-core/build/UniswapV2Factory.json'
import RouterArtifact  from '@uniswap/v2-periphery/build/UniswapV2Router02.json'
import WETHArtifact from '@uniswap/v2-periphery/build/WETH9.json'

const { abi: FactoryABI, bytecode: FactoryBytecode } = FactoryArtifact
const { abi: RouterABI, bytecode: RouterBytecode } = RouterArtifact
const { abi: WETHABI, bytecode: WETHBytecode } = WETHArtifact

async function main() {
    const [deployer, marketingWallet] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Marketing wallet:", marketingWallet.address);

    // Step 1: Deploy WETH
    console.log("\n1. Deploying WETH...");
    const WETH = new ethers.ContractFactory(WETHABI, WETHBytecode, deployer);
    const weth = await WETH.deploy();
    await weth.waitForDeployment();
    console.log("WETH deployed to:", await weth.getAddress());

    // Step 2: Deploy Uniswap V2 Factory
    console.log("\n2. Deploying UniswapV2Factory...");
    const Factory = new ethers.ContractFactory(FactoryABI, FactoryBytecode, deployer);
    const factory = await Factory.deploy(deployer.address); // feeTo set to deployer
    await factory.waitForDeployment();
    console.log("UniswapV2Factory deployed to:", await factory.getAddress());

    // Step 3: Deploy Uniswap V2 Router
    console.log("\n3. Deploying UniswapV2Router02...");
    const Router = new ethers.ContractFactory(RouterABI, RouterBytecode, deployer);
    const router = await Router.deploy(await factory.getAddress(), await weth.getAddress());
    await router.waitForDeployment();
    const routerAddress = await router.getAddress();
    console.log("UniswapV2Router02 deployed to:", routerAddress);

    // Step 4: Deploy MemeToken
    console.log("\n4. Deploying MemeToken...");
    const MemeToken = await ethers.getContractFactory("MemeToken");
    const memetoken = await MemeToken.deploy(routerAddress, marketingWallet.address);
    await memetoken.waitForDeployment();
    const memetokenAddress = await memetoken.getAddress();
    console.log("MemeToken deployed to:", memetokenAddress);

    // 验证交易对是否已创建
    const pairAddress = await memetoken.uniswapV2Pair();
    console.log("MemeToken-WETH Pair Address:", pairAddress);
    if (pairAddress === ethers.ZeroAddress) {
        throw new Error("Failed to create pair during deployment!");
    }

    // Step 5: 授权并添加初始流动性
    console.log("\n5. Adding initial liquidity...");

    const tokenAmount = ethers.parseUnits("500", 18); // 500 LMEME
    const ethAmount = ethers.parseEther("1");        // 1 ETH

    // 发送 ETH 到代币合约（用于添加流动性）
    console.log(`Sending ${ethers.formatEther(ethAmount)} ETH to contract...`);
    await deployer.sendTransaction({ to: memetokenAddress, value: ethAmount });

    // 授权 Router 使用代币
    console.log("Approving Router to spend MemeToken...");
    await memetoken.approve(routerAddress, tokenAmount);

    // 调用 addInitialLiquidity
    console.log("Calling addInitialLiquidity...");
    const tx = await memetoken.addInitialLiquidity(tokenAmount, ethAmount);
    await tx.wait();
    console.log("✅ Initial liquidity added successfully!");

    // 输出最终信息
    console.log("\n--- Deployment Summary ---");
    console.log("WETH Address:", await weth.getAddress());
    console.log("UniswapV2Factory Address:", await factory.getAddress());
    console.log("UniswapV2Router Address:", routerAddress);
    console.log("MemeToken Address:", memetokenAddress);
    console.log("LP Pair Address:", pairAddress);
    console.log("Marketing Wallet:", marketingWallet.address);
    console.log("Initial Liquidity: 500 LMEME + 1 ETH");
    console.log("---------------------------");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Deployment failed:", error);
        process.exit(1);
    });