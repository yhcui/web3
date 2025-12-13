# DuggeeToken 合约部署和操作指南

## 项目概述

DuggeeToken 是一个基于 SHIB 风格的 Meme 代币项目，包含三个核心合约：

1. **DuggeeToken.sol** - 主代币合约，实现交易税、交易限制等功能
2. **DuggeeTokenPool.sol** - 流动性池合约，支持代币交换和流动性管理
3. **DuggeeTokenPoolManager.sol** - 流动性池管理器，用于创建和管理多个流动性池

## 合约功能特性

### DuggeeToken 合约
- ✅ ERC20 标准代币功能
- ✅ **交易税机制**：默认 5% 税率，自动分配给合约所有者
- ✅ **交易限制**：
  - 单笔交易最大额度：1000 DUG（可调节）
  - 每日交易次数限制：10 次（可调节）
- ✅ **防操纵保护**：限制大额交易和机器人操作

### DuggeeTokenPool 合约
- ✅ **流动性管理**：用户可以添加和移除流动性
- ✅ **代币交换**：支持 DuggeeToken 与其他 ERC20 代币的双向交换
- ✅ **交易费用**：默认 0.1% 交易手续费
- ✅ **恒定乘积算法**：基于 x*y=k 的 AMM 机制
- ✅ **LP 代币**：流动性提供者获得 LP 代币凭证

### DuggeeTokenPoolManager 合约
- ✅ **工厂模式**：为不同代币创建独立的流动性池
- ✅ **池子管理**：记录和管理所有流动性池
- ✅ **地址查询**：快速查找特定代币的流动性池

## 部署指南

### 环境准备

1. **安装依赖**
```bash
npm install
```

2. **配置 Hardhat**
确保 `hardhat.config.ts` 配置正确：
```typescript
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
  },
  networks: {
    hardhat: {},
    // 配置你的网络（如 sepolia, mainnet 等）
  },
};

export default config;
```

### 部署步骤

#### 第一步：部署 DuggeeToken 合约

```javascript
// scripts/deploy.js
const hre = require("hardhat");

async function main() {
  console.log("开始部署 DuggeeToken 合约...");

  // 部署代币合约，初始供应量 1,000,000 DUG
  const DuggeeToken = await hre.ethers.getContractFactory("DuggeeToken");
  const initialSupply = hre.ethers.parseUnits("1000000", 18); // 1,000,000 DUG
  const duggeeToken = await DuggeeToken.deploy(initialSupply);

  await duggeeToken.waitForDeployment();
  const duggeeTokenAddress = await duggeeToken.getAddress();

  console.log("✅ DuggeeToken 合约部署成功！");
  console.log("合约地址:", duggeeTokenAddress);
  console.log("初始供应量:", hre.ethers.formatUnits(initialSupply, 18), "DUG");

  return duggeeTokenAddress;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

#### 第二步：部署 DuggeeTokenPoolManager 合约

```javascript
// scripts/deploy-manager.js
const hre = require("hardhat");

async function main() {
  const duggeeTokenAddress = "0x..."; // 替换为实际的 DuggeeToken 地址

  console.log("开始部署 DuggeeTokenPoolManager 合约...");

  const PoolManager = await hre.ethers.getContractFactory("DuggeeTokenPoolManager");
  const poolManager = await PoolManager.deploy(duggeeTokenAddress);

  await poolManager.waitForDeployment();
  const poolManagerAddress = await poolManager.getAddress();

  console.log("✅ DuggeeTokenPoolManager 合约部署成功！");
  console.log("合约地址:", poolManagerAddress);

  return poolManagerAddress;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

#### 运行部署命令

```bash
# 部署到本地测试网络
npx hardhat run scripts/deploy.js --network localhost

# 部署到测试网络（如 sepolia）
npx hardhat run scripts/deploy.js --network sepolia
```

## 使用指南

### 1. 代币操作

#### 查询代币信息
```javascript
// 连接合约
const duggeeToken = await hre.ethers.getContractAt("DuggeeToken", duggeeTokenAddress);

// 查询代币基本信息
const name = await duggeeToken.name();           // "DuggeeToken"
const symbol = await duggeeToken.symbol();       // "DUG"
const totalSupply = await duggeeToken.totalSupply();
const decimals = await duggeeToken.decimals();   // 18

console.log("代币名称:", name);
console.log("代币符号:", symbol);
console.log("总供应量:", hre.ethers.formatUnits(totalSupply, decimals), "DUG");
```

#### 转账代币
```javascript
// 注意：转账会自动扣除 5% 税费
const recipient = "0x...";           // 接收地址
const amount = hre.ethers.parseUnits("100", 18);  // 转账 100 DUG

const tx = await duggeeToken.transfer(recipient, amount);
await tx.wait();

console.log("转账成功！实际到账金额:", hre.ethers.formatUnits(amount * 95n / 100n, 18), "DUG");
console.log("税费金额:", hre.ethers.formatUnits(amount * 5n / 100n, 18), "DUG");
```

#### 授权转账
```javascript
// 先授权，然后转账（同样会扣除税费）
const spender = "0x...";            // 被授权地址
const amount = hre.ethers.parseUnits("200", 18);  // 授权 200 DUG

// 授权操作
await duggeeToken.approve(spender, amount);

// 被授权地址执行转账
const duggeeTokenWithSigner = duggeeToken.connect(await hre.ethers.getSigner(spender));
await duggeeTokenWithSigner.transferFrom(yourAddress, recipient, amount);
```

### 2. 流动性池操作

#### 创建流动性池
```javascript
// 连接池管理器合约
const poolManager = await hre.ethers.getContractAt("DuggeeTokenPoolManager", poolManagerAddress);

// 配对代币地址（例如：USDT）
const pairTokenAddress = "0x...";  // 替换为实际的配对代币地址

// 创建新的流动性池
const tx = await poolManager.createPool(pairTokenAddress);
await tx.wait();

console.log("流动性池创建成功！");

// 查询池子地址
const poolAddress = await poolManager.getPool(pairTokenAddress);
console.log("池子地址:", poolAddress);
```

#### 添加流动性
```javascript
// 连接流动性池合约
const pool = await hre.ethers.getContractAt("DuggeeTokenPool", poolAddress);

const duggeeAmount = hre.ethers.parseUnits("1000", 18);    // 添加 1000 DUG
const tokenAmount = hre.ethers.parseUnits("500", 6);       // 添加 500 USDT（假设6位小数）
const minTokenAmount = hre.ethers.parseUnits("490", 6);    // 最少接受 490 USDT（防滑点）

// 先授权池子合约操作代币
await duggeeToken.approve(poolAddress, duggeeAmount);
const pairToken = await hre.ethers.getContractAt("IERC20", pairTokenAddress);
await pairToken.approve(poolAddress, tokenAmount);

// 添加流动性
const tx = await pool.addLiquidity(duggeeAmount, tokenAmount, minTokenAmount);
await tx.wait();

console.log("流动性添加成功！");

// 查询 LP 代币余额
const lpBalance = await pool.lpTokens(yourAddress);
console.log("获得 LP 代币:", hre.ethers.formatUnits(lpBalance, 18));
```

#### 移除流动性
```javascript
const lpTokenAmount = hre.ethers.parseUnits("500", 18);  // 移除 500 LP 代币

const tx = await pool.removeLiquidity(lpTokenAmount);
await tx.wait();

console.log("流动性移除成功！");

// 查询池子状态
const duggeeReserve = await pool.duggeeReserve();
const tokenReserve = await pool.tokenReserve();
console.log("DUG 储备量:", hre.ethers.formatUnits(duggeeReserve, 18));
console.log("配对代币储备量:", hre.ethers.formatUnits(tokenReserve, 6));
```

### 3. 代币交换

#### DuggeeToken 交换为配对代币
```javascript
const fromAmount = hre.ethers.parseUnits("100", 18);     // 卖出 100 DUG
const minToAmount = hre.ethers.parseUnits("45", 6);      // 最少获得 45 USDT

// 授权池子合约操作 DUG
await duggeeToken.approve(poolAddress, fromAmount);

// 执行交换
const tx = await pool.swap(duggeeTokenAddress, fromAmount, minToAmount);
await tx.wait();

console.log("交换成功！");
```

#### 配对代币交换为 DuggeeToken
```javascript
const fromAmount = hre.ethers.parseUnits("50", 6);       // 卖出 50 USDT
const minToAmount = hre.ethers.parseUnits("90", 18);     // 最少获得 90 DUG

// 授权池子合约操作配对代币
const pairToken = await hre.ethers.getContractAt("IERC20", pairTokenAddress);
await pairToken.approve(poolAddress, fromAmount);

// 执行交换
const tx = await pool.swap(pairTokenAddress, fromAmount, minToAmount);
await tx.wait();

console.log("交换成功！");
```

### 4. 价格查询

```javascript
// 获取当前价格（1 DUG 能兑换多少配对代币）
const price = await pool.getPrice();
console.log("当前价格:", hre.ethers.formatUnits(price, 18), "配对代币 / DUG");

// 计算估算交换数量（不包含费用）
const inputAmount = hre.ethers.parseUnits("100", 18);  // 100 DUG
const estimatedOutput = (inputAmount * await pool.tokenReserve()) /
                       (await pool.duggeeReserve() + inputAmount);
console.log("估算输出:", hre.ethers.formatUnits(estimatedOutput, 6), "配对代币");
```

### 5. 管理员操作

#### 修改 DuggeeToken 参数
```javascript
// 只有合约所有者可以执行

// 设置交易税率（0-20%）
await duggeeToken.setTaxPercentage(3);  // 设置为 3%

// 设置单笔交易最大额度
await duggeeToken.setMaxTxAmount(hre.ethers.parseUnits("5000", 18));  // 5000 DUG

// 查询当前设置
const currentTax = await duggeeToken.taxPercentage();
const currentMaxTx = await duggeeToken.maxTxAmount();
console.log("当前税率:", currentTax.toString(), "%");
console.log("当前最大交易额度:", hre.ethers.formatUnits(currentMaxTx, 18), "DUG");
```

#### 修改流动性池参数
```javascript
// 设置交易费率（千分比，0.1-10%）
await pool.setFeePercentage(2);  // 设置为 2‰ (0.2%)

// 提取交易费用
await pool.withdrawFees();
console.log("手续费提取成功！");

// 查询当前费用余额
const duggeeFees = await pool.duggeeTokenFeeBalance();
const tokenFees = await pool.tokenFeeBalance();
console.log("DUG 手续费余额:", hre.ethers.formatUnits(duggeeFees, 18));
console.log("配对代币手续费余额:", hre.ethers.formatUnits(tokenFees, 6));
```

## 安全注意事项

### 🚨 重要提醒

1. **私钥安全**
   - 永远不要泄露私钥或助记词
   - 使用硬件钱包进行重要操作
   - 定期轮换管理员私钥

2. **合约安全**
   - 部署前进行充分测试
   - 建议使用专业的安全审计
   - 设置合理的交易限制

3. **交易风险**
   - 注意滑点风险，设置合理的 `minToAmount`
   - 了解无常损失的风险
   - 谨慎设置交易税率和交易限制

4. **流动性管理**
   - 初期流动性提供者设定初始价格
   - 大额移除流动性会影响价格
   - 监控池子的健康状态

### 📋 检查清单

部署前检查：
- [ ] 代币初始供应量设置合理
- [ ] 交易税率在合理范围（建议 0-20%）
- [ ] 交易限制设置合理
- [ ] 所有合约地址已验证
- [ ] 充足的测试覆盖

操作前检查：
- [ ] 网络状态正常
- [ ] Gas 费用合理
- [ ] 授权金额正确
- [ ] 接收地址验证
- [ ] 滑点保护设置

## 常见问题解答

### Q: 如何查看我的交易次数限制？
```javascript
const dailyTxCount = await duggeeToken.dailyTxCount(yourAddress);
const currentDay = await duggeeToken.lastTxDay(yourAddress);
console.log("今日交易次数:", dailyTxCount.toString());
console.log("最后交易日期:", currentDay.toString());
```

### Q: LP 代币可以转账吗？
是的，LP 代币是标准的 ERC20 代币，可以自由转账、交易或在其他 DeFi 协议中使用。

### Q: 如何计算交换后的实际数量？
实际输出 = (输入金额 × 当前储备量) / (当前储备量 + 输入金额) - 手续费
手续费 = 输入金额 × 费率

### Q: 池子的价格如何确定？
价格 = 配对代币储备量 / DuggeeToken 储备量
通过买卖行为自动调整，遵循供需关系。

### Q: 如果池子没有流动性怎么办？
当池子储备量为 0 时，任何交换操作都会失败。需要有流动性提供者先添加流动性。

---

**免责声明**: 本指南仅供教育和参考目的。使用智能合约涉及风险，请在充分理解相关风险后进行操作。