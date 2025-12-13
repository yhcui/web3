# Sample Hardhat 3 Beta Project (`mocha` and `ethers`)## 一、项目概述

`MemeToken` 智能合约，涵盖代币创建、交易、添加/移除流动性、设置钱包地址等关键操作。该合约基于 Solidity 0.8 编写，继承自 OpenZeppelin 的 `ERC20` 和 `Ownable`，并集成了 Uniswap V2 路由器与交易对功能，具备自动税收分配与流动性添加机制。

## 二、合约核心特性概览

-   **代币总量**：1000 LMEME（18 位小数）
-   **买入税**：5%（用于营销 + 流动性）
-   **卖出税**：8%（用于营销 + 流动性）
-   **税费分配**：50% 营销钱包，50% 自动添加流动性
-   **交易冷却**：卖出后需等待 5 秒才能再次卖出
-   **最大单笔交易**：10% 总供应量（即 100 LMEME）
-   **自动做市**：卖出时自动将部分代币兑换为 ETH 并添加流动性
-   **免税地址**：合约自身、部署者、零地址、交易对、路由器
-   **测试**：支持在 Hardhat 环境中本地网络测试（含 console.log 调试）

## 三、部署前准备

**确保已安装以下工具**：

-   Node.js（v22+）
-   npm
-   pnpm
-   Hardhat

```markdown
git clone https://github.com/your-username/meme-token.git
pnpm install
```

## **四、测试与部署合约**

### **1. 测试合约**

在项目根目录下运行以下命令进行测试：

```markdown
 # 测试solidity
 pnpm hardhat test solidity xxxxx.t.sol
 # 测试js/ts脚本
 pnpm hardhat test xxxxx.ts
 # 运行脚本
 pnpm hardhat run xxxxx.ts
```

### **2. 部署合约**

    合约部署脚本：scripts/deploy.ts
    合约升级脚本：scripts/update.ts

部署命令：

```markdown
# 需要提前在 hardhat.config.js 中配置好网络信息

# 需要提前设置好网络 rpc 地址和私钥，以及其它变量

pnpm dlx hardhat vars set SEPOLIA_RPC_URL
pnpm dlx hardhat vars set SEPOLIA_PRIVATE_KEY

# 部署合约
pnpm dlx hardhat run scripts/deploy.js --network <网络名称>
```

部署成功后会输出：代币合约地址，交易对地址（Pair）等信息

## **五、部署合约添加初始流动性**

**注意**：必须先向合约地址转入 ETH，再调用 addInitialLiquidity。

-   **发送 ETH 到合约地址**：使用钱包（如 MetaMask）向部署后的合约地址发送至少 0.1 ETH
-   **调用 **`**addInitialLiquidity**`** 函数**：

```markdown
// 示例调用（使用 ethers.js）
await token.addInitialLiquidity(
ethers.utils.parseEther("500"), // 500 MEME
ethers.utils.parseEther("1") // 1 ETH
);
```

## 六、代币交易规则

### **1. 买入代币（Buy）**

用户向交易对（Pair）发送 ETH，换取 MEME。

-   **税率**：`5%`（从买入金额中扣除）
-   **去向**：
    -   2.5% → 营销钱包
    -   2.5% → 合约（后续用于流动性）
-   无冷却时间限制。

### **2. 卖出代币（Sell）**

用户向交易对发送 LMEME，换取 ETH。

-   **税率**：`8%`
-   **去向**：
    -   4% → 营销钱包
    -   4% → 合约 → 自动兑换为 ETH 并添加流动性
-   **冷却时间**：卖出后需等待 `5 秒` 才能再次卖出
-   若 swapAndLiquifyEnabled == false，则 4% 的流动性部分仍进入合约，但不执行添加。

## 七、关键功能操作

### 1. **设置最大交易额度**

仅限 **Owner** 调用。

```markdown
await token.setMaxTxAmount(ethers.utils.parseEther("200")); // 设置为 200 MEME
```

### 2. **切换自动流动性功能**

```markdown
await token.updateSwapAndLiquifyEnabled(true); // 开启
await token.updateSwapAndLiquifyEnabled(false); // 关闭
```

## **八、免税与权限说明**

| **地址**          | **是否免税** | **说明** |
| ----------------- | ------------ | -------- |
| `owner()`         | ✅           | 部署者   |
| `address(this)`   | ✅           | 合约自身 |
| `uniswapV2Pair`   | ✅           | 交易对   |
| `uniswapV2Router` | ✅           | 路由器   |
| `address(0)`      | ✅           | 零地址   |
| 其他用户          | ❌           | 正常征税 |

免税地址之间转账不触发税收逻辑。

## 九、监控与调试

### 1. **事件日志**

合约触发以下事件：

| **事件**                 | **说明**                         |
| ------------------------ | -------------------------------- |
| `SwapAndLiquify`         | 成功添加流动性                   |
| `SwapAndLiquifyFailure`  | 兑换失败                         |
| `AddLiquidityFailure`    | 添加流动性失败                   |
| `MarketingWalletChanged` | 营销钱包变更（当前仅部署时触发） |
