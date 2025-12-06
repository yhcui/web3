// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IPositionManager is IERC721 {
    struct PositionInfo {
        uint256 id; // 头寸 ID。该头寸的唯一标识符，通常是与 NFT Token ID 对应
        address owner; //所有者地址。拥有该流动性头寸 NFT 的用户钱包地址
        address token0;
        address token1;
        uint32 index; // Pool 索引。用于在 Factory 中唯一标识 (token0, token1) 交易对中的特定 Pool（在多个费率或 Tick 范围的 Pool 中）
        uint24 fee; // 交易费率。该头寸所属 Pool 的费率，例如 $0.05\%$, $0.3\%$ 等。
        uint128 liquidity; // 流动性数量L。该头寸当前贡献的有效流动性数量。这是计算 LP 份额、价格变动影响和手续费的关键数值。
        int24 tickLower;
        int24 tickUpper;
        uint128 tokensOwed0; // 未领取的手续费 Token0。该头寸已累计但尚未被 LP 领取的 Token0 数量（不包含本金）。
        uint128 tokensOwed1;// 未领取的手续费 Token1。该头寸已累计但尚未被 LP 领取的 Token1 数量（不包含本金）。
        // feeGrowthInside0LastX128 和 feeGrowthInside1LastX128 用于计算手续费
        uint256 feeGrowthInside0LastX128; // 上次结算时 Token0 的内部费用增长(内部费用即交易费率fee计算得来的)。这是一个记账变量。它记录了LP(owner)上次操作（mint 或 collect）时，其tickLower 和 tickUpper 边界内Token0 的累计费用增长值。
        uint256 feeGrowthInside1LastX128;
    }

    function getAllPositions()
        external
        view
        returns (PositionInfo[] memory positionInfo);

    /*
    index：用户在前端选择费率等级（例如 0.3\%）。前端或 Router 会根据Token0,Token1,Fee) 组合，查询 PoolManager 的索引来确定这个 Pool 的唯一标识符 index
    隐含参数：tickLower 和 tickUpper虽然这两个参数不在 MintParams 结构体中，但它们是铸造头寸所必需的。Tick被硬编码在了 Pool 合约中
    这里不需要专入费率么？--需要，根据 Token 对和 index 的组合来确定一个唯一的 Pool 地址,Pool中有fee
    */
    struct MintParams {
        address token0; // Token0 地址。该头寸所属交易对的 Token0合约地址。用户输入（通过前端界面选择代币）
        address token1;// Token1 地址。该头寸所属交易对的 Token1合约地址。用户输入（通过前端界面选择代币）
        uint32 index; // Pool 索引。用于在 PoolManager 中查找指定 Token 对和 Fee 对应的 Pool。系统计算/查找（用户选择费率，系统查找对应 Index）
        uint256 amount0Desired; // Token0 期望投入数量。用户希望投入的最大 Token0 数量。用户输入
        uint256 amount1Desired;  // Token1 期望投入数量。用户希望投入的最大 Token1数量。用户输入
        address recipient; // 头寸 NFT 接收方地址。铸造的 Position NFT 的接收地址。用户输入（通常是 msg.sender，但也可以是第三方地址）
        uint256 deadline; // 交易截止时间。交易可以被执行的 Unix 时间戳最大值。  系统计算（当前时间 $+$ 预设的有效窗口时间，例如 20 分钟）
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function burn(
        uint256 positionId
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        uint256 positionId,
        address recipient
    ) external returns (uint256 amount0, uint256 amount1);

    function mintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
