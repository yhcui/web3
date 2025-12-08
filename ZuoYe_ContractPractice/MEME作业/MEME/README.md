# MEME 代币系列教学作业

本项目实现了一个 SHIB 风格的 MEME 代币合约，包含代币税、流动性池集成和交易限制功能。

## 📁 项目结构

```
MEME/
├── contracts/
│   └── ShibaMemeCoin.sol          # 主合约文件
├── scripts/
│   ├── deploy.js                  # 部署脚本
│   └── interact.js                # 交互脚本
├── docs/
│   ├── 理论知识梳理.md             # 理论分析文档
│   └── 操作指南.md                # 操作指南文档
├── deployments/                   # 部署信息存储
└── README.md                      # 项目说明
```

## 🚀 快速开始

### 1. 环境准备

```bash
# 安装依赖
npm install --save-dev hardhat @openzeppelin/contracts @nomiclabs/hardhat-ethers ethers

# 配置 hardhat.config.js
# 设置网络配置和私钥
```

### 2. 合约部署

```bash
# 本地部署
npx hardhat node
npx hardhat run scripts/deploy.js --network localhost

# 测试网部署
npx hardhat run scripts/deploy.js --network goerli
```

### 3. 合约交互

```bash
# 运行交互脚本
npx hardhat run scripts/interact.js --network localhost
```

## 📋 作业完成情况

### ✅ 理论知识梳理

- [x] 代币税机制分析
- [x] 流动性池原理探究
- [x] 交易限制策略探讨
- [x] SHIB 案例分析

文档位置：`docs/理论知识梳理.md`

### ✅ 智能合约实现

#### 代币税功能
- [x] 买入税机制（默认5%）
- [x] 卖出税机制（默认8%）
- [x] 转账税机制（默认2%）
- [x] 税费自动分配到营销、流动性、销毁等用途

#### 流动性池集成
- [x] Uniswap V2 集成
- [x] 自动流动性添加
- [x] 流动性池检测
- [x] 代币与ETH自动交换

#### 交易限制功能
- [x] 最大交易量限制（默认1%）
- [x] 最大持有量限制（默认2%）
- [x] 交易时间间隔限制（默认30秒）
- [x] 黑名单机制

### ✅ 高级功能

- [x] 反射奖励机制
- [x] 代币销毁功能
- [x] 费用豁免系统
- [x] 紧急暂停机制
- [x] 所有者权限管理

### ✅ 操作指南

详细的部署和使用指南：`docs/操作指南.md`

- [x] 环境准备说明
- [x] 合约部署步骤
- [x] 基本操作说明
- [x] 高级功能使用
- [x] 故障排除指南

## 🔧 核心功能介绍

### 代币基本信息
- **名称**: ShibaMemeCoin
- **符号**: SMEME
- **总供应量**: 1,000,000,000,000,000 枚 (1000万亿)
- **精度**: 18位小数

### 税费配置
- **买入税**: 5% (可调整)
- **卖出税**: 8% (可调整)
- **转账税**: 2% (可调整)
- **流动性费用**: 2%
- **反射奖励**: 3%
- **销毁费用**: 1%
- **营销费用**: 4%

### 交易限制
- **最大单笔交易**: 总供应量的1%
- **最大持有量**: 总供应量的2%
- **交易间隔**: 30秒冷却期
- **黑名单**: 支持地址黑名单功能

## 🛡️ 安全特性

1. **所有者权限控制**: 关键功能仅所有者可调用
2. **重入攻击防护**: 使用 ReentrancyGuard
3. **溢出保护**: 使用 SafeMath 库
4. **紧急机制**: 支持紧急暂停和资金提取
5. **黑名单功能**: 可限制恶意地址交易

## 📊 合约状态查询

```javascript
// 获取代币基本信息
const tokenInfo = await contract.getTokenInfo();

// 获取费用配置
const feeInfo = await contract.getFeeInfo();

// 获取限制配置
const limitInfo = await contract.getLimitInfo();
```

## 🎯 教学目标达成

本项目通过实际合约开发，让学生掌握：

1. **MEME代币经济模型设计原理**
2. **Solidity智能合约开发实践**
3. **Uniswap流动性池集成技术**
4. **代币税和交易限制实现**
5. **智能合约安全最佳实践**

## 📝 代码特点

- **详细注释**: 每个函数都有完整的中文注释
- **模块化设计**: 功能模块清晰分离
- **可配置参数**: 支持运行时参数调整
- **事件记录**: 重要操作都有事件日志
- **错误处理**: 完善的错误检查和处理

## 🚨 使用注意事项

1. **测试先行**: 请在测试网充分测试后再部署到主网
2. **参数验证**: 部署前仔细检查所有配置参数
3. **私钥安全**: 妥善保管私钥，建议使用硬件钱包
4. **合约验证**: 主网部署后及时进行合约验证
5. **风险提示**: MEME代币具有高风险，请谨慎投资

## 📖 相关资源

- [Solidity 官方文档](https://docs.soliditylang.org/)
- [OpenZeppelin 合约库](https://openzeppelin.com/contracts/)
- [Uniswap V2 文档](https://docs.uniswap.org/protocol/V2/introduction)
- [Hardhat 开发工具](https://hardhat.org/docs)

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request 来改进项目：

1. Fork 本仓库
2. 创建特性分支
3. 提交更改
4. 创建 Pull Request

---

**⚠️ 免责声明**: 本项目仅用于教学目的，不构成投资建议。智能合约涉及资金风险，请在充分理解后使用。