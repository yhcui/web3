# SHIB风格Meme代币合约

## 项目概述

ShibaMemeToken是一个基于以太坊ERC20标准的Meme代币合约，采用Hardhat开发框架，集成了现代DeFi代币的核心机制。

### 亮点

**自动流动性** - 税费自动添加到Uniswap流动性池  
**交易限制** - 单笔限额、最大持有量、冷却期 

**反机器人** - 启动保护、黑名单、夹子防护

**安全设计** - OpenZeppelin库、防重入、权限控制

**完整测试** - 全面的单元测试覆盖

**代币税机制** - 灵活的买入/卖出税配置

## 核心功能

###   1. 代币税机制

#### 税率配置

- **买入税**：默认 5% (可调整 0-25%)
- **卖出税**：默认 10% (可调整 0-25%)
- **启动保护**：前10个区块 99% 税率防夹子攻击

#### 自动处理

- 累积税费达到阈值时自动触发
- 自动swap代币为ETH
- 自动添加流动性到Uniswap
- 自动分配ETH给营销和开发钱包

### 2. 流动性池集成

#### Uniswap V2集成

- 自动创建交易对 (Token/ETH)
- 支持自动添加流动性
- LP代币发送给指定钱包
- 防止流动性被套利

#### 流动性保护

- 流动性钱包可配置
- 支持流动性锁定
- 防止Rug Pull机制

### 3. 交易限制策略

#### 三层限制机制

**1. 单笔交易限额**

```solidity
默认：总供应量的 0.5%
可调整范围：最低 0.1%
```

**2. 最大持有量限制**

```solidity
默认：总供应量的 2%
可调整范围：最低 1%
豁免：流动性池、合约、Owner
```

**3. 冷却期机制**

```solidity
默认：60秒
可调整范围：0-300秒
防止高频交易和机器人
```

#### 豁免机制

- Owner自动豁免
- 合约地址豁免
- 流动性池豁免
- 可手动设置豁免地址

### 4. 黑名单功能

- 支持单个地址黑名单
- 支持批量设置黑名单
- 黑名单地址无法转入/转出
- 用于反欺诈和合规要求

### 5. 安全特性

- **防重入攻击**：使用ReentrancyGuard
- **权限控制**：Ownable权限管理
- **安全数学**：Solidity 0.8+ 内置溢出保护
- **标准库**：使用OpenZeppelin审计过的库
- **紧急功能**：资金救援、暂停交易

---

## 技术架构

### 合约架构

```
ShibaMemeToken
├── ERC20 (OpenZeppelin)
│   ├── 基础代币功能
│   └── _update() 重写
├── Ownable (OpenZeppelin)
│   └── 权限管理
├── ReentrancyGuard (OpenZeppelin)
│   └── 防重入保护
└── IShibaMeme (自定义接口)
    ├── 税费管理
    ├── 限制管理
    └── 黑名单管理
```

## 快速开始

### 安装依赖

```
npm install
```

### 编译合约

```bash
npx hardhat compile
```

### 运行测试

```bash
# 运行所有测试
npx hardhat test

# 运行特定测试
npx hardhat test test/test.js

# 查看测试覆盖率
npx hardhat coverage

# 显示Gas报告
REPORT_GAS=true npx hardhat test
```

---

## 部署指南

### 1. 配置环境变量

复制环境变量模板：

```bash
cp .env.example .env
```

编辑 `.env` 文件：

```env
# Sepolia测试网RPC
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# 部署账户私钥
PRIVATE_KEY=your_private_key_here

# Etherscan API Key（用于合约验证）
ETHERSCAN_API_KEY=your_etherscan_api_key

# 可选：营销和开发钱包地址
MARKETING_WALLET=0x...
DEV_WALLET=0x...
```

### 2. 部署到本地测试网

```bash
# 启动本地Hardhat网络
npx hardhat node

# 在新终端部署合约
npx hardhat run scripts/deploy.js --network localhost
```

### 3. 部署到Sepolia测试网

```bash
npx hardhat run scripts/deploy.js --network sepolia
```

### 4. 验证合约

部署成功后，使用Etherscan验证：

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> \
  "Shiba Meme Token" \
  "SHIBM" \
  "1000000000000000000000000000000" \
  "<ROUTER_ADDRESS>" \
  "<MARKETING_WALLET>" \
  "<DEV_WALLET>"
```

---



## 许可证



MIT License
