// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libraries/LiquidityAmounts.sol";
import "./libraries/TickMath.sol";
import "./libraries/FixedPoint128.sol";

import "./interfaces/IPositionManager.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IPoolManager.sol";

/*
PoolManager 侧重于池子的创建和发现
PositionManager 侧重于流动性头寸（即用户的 LP 份额）的管理
PositionManager 是协议的用户接口和流动性头寸的管理中心。它的职责是允许用户安全、方便地管理他们的流动性份额，并领取收益
流动性头寸 (Position):用户的 LP 份额，通常以 NFT（非同质化代币）的形式表示，每个 NFT 对应一个独特的 Token 对、费率、tickLower 和 tickUpper 组合。
*/
contract PositionManager is IPositionManager, ERC721 {
    // 保存 PoolManager 合约地址
    IPoolManager public poolManager;

    /// @dev The ID of the next token that will be minted. Skips 0
    // 通常用于跟踪下一个可用的头寸 ID。头寸 ID 通常从 1 开始计数。
    uint176 private _nextId = 1;

    constructor(address _poolManger) ERC721("MetaNodeSwapPosition", "MNSP") {
        poolManager = IPoolManager(_poolManger);
    }

    // 用一个 mapping 来存放所有 Position 的信息
    mapping(uint256 => PositionInfo) public positions;

    // 获取全部的 Position 信息
    // 所有用户 的头寸，因为这些头寸都是由该合约集中管理的
    /**
    
     在真实的区块链应用中，这种设计虽然功能上是可行的，但存在一些重要的实际问题：
     Gas 限制： 随着头寸数量的增加，_nextId - 1 也会无限增加。在以太坊这样的链上，如果头寸数量过多，执行 getAllPositions() 函数可能会因为超出区块 Gas 限制而失败。
     数据冗余： 通常不会在链上直接提供一个查询所有用户所有头寸的函数。更常见的做法是提供：
     positions(uint256 tokenId)：查询特定 ID 的头寸。
     链下索引： 依靠 The Graph 或其他链下索引服务来监听 Mint、Burn 等事件，然后在链下数据库中重建并查询所有头寸列表。 
     
    */
    function getAllPositions()
        external
        view
        override
        returns (PositionInfo[] memory positionInfo)
    {
        positionInfo = new PositionInfo[](_nextId - 1);
        for (uint32 i = 0; i < _nextId - 1; i++) {
            positionInfo[i] = positions[i + 1];
        }
        return positionInfo;
    }

    function getSender() public view returns (address) {
        return msg.sender;
    }

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
    //防止交易过期: checkDeadline 检查当前区块链时间 (block.timestamp) 是否小于或等于用户在交易参数中设定的 截止时间（deadline）
    modifier checkDeadline(uint256 deadline) {
        require(_blockTimestamp() <= deadline, "Transaction too old");
        _;
    }
    // 允许用户创建（铸造）一个新的集中流动性头寸，并将其投入到指定的流动性池（Pool）中
    function mint(
        MintParams calldata params
    )
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // mint 一个 NFT 作为 position 发给 LP
        // NFT 的 tokenId 就是 positionId
        // 通过 MintParams 里面的 token0 和 token1 以及 index 获取对应的 Pool
        // 调用 poolManager 的 getPool 方法获取 Pool 地址
        address _pool = poolManager.getPool(
            params.token0,
            params.token1,
            params.index
        );
        IPool pool = IPool(_pool);

        // 通过获取 pool 相关信息，结合 params.amount0Desired 和 params.amount1Desired 计算这次要注入的流动性

        uint160 sqrtPriceX96 = pool.sqrtPriceX96();
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(pool.tickLower());
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(pool.tickUpper());

        // TODO CUIYUHUI
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            params.amount0Desired,
            params.amount1Desired
        );

        // data 是 mint 后回调 PositionManager 会额外带的数据
        // 需要 PoistionManger 实现回调，在回调中给 Pool 打钱
        bytes memory data = abi.encode(
            params.token0,
            params.token1,
            params.index,
            msg.sender
        );

        (amount0, amount1) = pool.mint(address(this), liquidity, data);
        // 分配新的头寸 ID。
        // 铸造 ERC-721 代币并分配给用户。
        _mint(params.recipient, (positionId = _nextId++));

        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.getPosition(address(this));

        positions[positionId] = PositionInfo({
            id: positionId,
            owner: params.recipient,
            token0: params.token0,
            token1: params.token1,
            index: params.index,
            fee: pool.fee(),
            liquidity: liquidity,
            tickLower: pool.tickLower(),
            tickUpper: pool.tickUpper(),
            tokensOwed0: 0,
            tokensOwed1: 0,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128
        });
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        address owner = ERC721.ownerOf(tokenId);
        require(_isAuthorized(owner, msg.sender, tokenId), "Not approved");
        _;
    }

    // 移除（销毁）流动性头寸 - 让流动性提供者（LP）取回他们之前投入的本金资产
    // 在这个特定的模型中，burn 负责移除流动性，而资产（本金和手续费）会被累加到头寸的应得余额中，等待单独的 collect 调用来提取。
    // 在这个模型中，burn 只是一个 记账和状态变更 的操作，它负责将流动性从 Pool 中移除，并将本金和收益结算到 tokensOwed 字段。
    // 它并不负责实际的 Token 转移。 Token 的实际提取（从Pool 转到用户地址）需要通过 collect 函数来完成。
    function burn(
        uint256 positionId
    )
        external
        override
        isAuthorizedForToken(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        PositionInfo storage position = positions[positionId];
        // 通过 isAuthorizedForToken 检查 positionId 是否有权限
        // 移除流动性，但是 token 还是保留在 pool 中，需要再调用 collect 方法才能取回 token
        // 通过 positionId 获取对应 LP 的流动性
        uint128 _liquidity = position.liquidity;
        // 调用 Pool 的方法给 LP 退流动性
        address _pool = poolManager.getPool(
            position.token0,
            position.token1,
            position.index
        );
        IPool pool = IPool(_pool);

        // 调用 Pool 的 burn（移除流动性） 要求 Pool 移除该头寸的所有 liquidity。
        // Pool 合约执行流动性移除计算，并返回该流动性对应的 本金数量：amount0 和 amount1。
        //  在这一步，Token资产并没有被转回给用户，而是被转移到 PositionManager 在 Pool 中的可提取余额中
        (amount0, amount1) = pool.burn(_liquidity);

        // 计算这部分流动性产生的手续费
        // 1. 获取 Pool 当前的费用增长快照
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.getPosition(address(this));

        // position.feeGrowthInside0LastX128 (头寸存储状态) 不是实时变动的。它是一个历史快照
        // position.feeGrowthInside0LastX128 就像一个时间戳或记账点，用于标记该 LP 上次结算收益时的 Tick 内部费用增长值。
        /**
         position.feeGrowthInside0LastX128 只在以下操作中被更新：mint (铸造/创建头寸)： 
         首次创建时，它被设置为当前的 Pool 实时值，作为该头寸开始赚取费用的 起始点。
         burn (移除流动性)： 在结算完所有应得收益后，它被更新为 burn 操作结束时的 Pool 实时值。
         collect (领取收益)： 在结算完所有应得收益后，它被更新为 collect 操作结束时的 Pool实时值。

         如何计算收益？
         （利用差值）正是因为 position.feeGrowthInsideLastX128 是一个固定不变的快照，才能用于计算收益。
         当 LP 想要结算时（例如在 burn 函数中）：
         查询实时值： 合约调用 pool.getPosition(address(this)) 获取当前时刻的 feeGrowthInside... 实时值。
         计算差额： 实时值 减去头寸中存储的 position.feeGrowthInsideLastX128。
         结算： 这个差额代表了 P_Start 到 P_End 期间该 Tick 区域内产生的费用，将其乘以头寸的 liquidity 即可结算收益。

         feeGrowthInside0LastX128 和 feeGrowthInside1LastX128，衡量的是 单位流动性（Unit of Liquidity） 赚取的费用增长量。
         费用增长字段的意义（单位流动性收益率）feeGrowthInside...X128 字段记录的是：每 1 单位流动性 $L$ 积累了多少手续费
         例如，如果feeGrowthInside增加了 100，这表示在这个时间段内，池子里的 每 1 单位 L 都赚了 100 份 Token0 的手续费（当然，这个 100 是经过 2^128 缩放的）
         
         为什么要乘以 liquidity？
         （LP 份额）仅仅知道 单位 L 赚了多少钱 是不够的，还需要知道这个特定的头寸贡献了多少 L。
         LP 的实际收益必须等于：单位 L 的收益率 X LP 贡献的 L 数量。

         为什么是 position.liquidity，而不是总流动性？
         在 CLMM 中，position.liquidity 是该 LP 头寸在特定 tick边界内贡献的 L 数量。
         手续费计算系统正是通过乘以这个头寸的私有流动性 L，实现了将 全局费用增长 转化为 该 LP 的具体收益份额 的业务目标
         

         */
        // 2. 累加本金和手续费到 tokensOwed
        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                // FullMath.mulDiv == a * b / c
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 -
                        position.feeGrowthInside0LastX128, // a: 费用增长差额 (分子)
                    position.liquidity,// b: 流动性数量 (分子)
                    FixedPoint128.Q128 // c: 缩放因子 2^128 (分母)
                )
            );

        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 -
                        position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

        // 更新 position 的信息
        // 更新快照： 更新 feeGrowthInside... 快照为本次结算时的值。即使 liquidity为 0，这个更新也是必要的，因为 LP 在collect 之前可能还有一些微小的尾部费用需要结算
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // 清零流动性： 将 position.liquidity 设为 0，标志着该头寸的流动性已经被完全移除
        position.liquidity = 0;
    }

    function collect(
        uint256 positionId,
        address recipient
    )
        external
        override
        isAuthorizedForToken(positionId)
        returns (uint256 amount0, uint256 amount1)
    {
        // 通过 isAuthorizedForToken 检查 positionId 是否有权限
        // 调用 Pool 的方法给 LP 退流动性
        PositionInfo storage position = positions[positionId];
        address _pool = poolManager.getPool(
            position.token0,
            position.token1,
            position.index
        );
        IPool pool = IPool(_pool);
        (amount0, amount1) = pool.collect(
            recipient,
            position.tokensOwed0,
            position.tokensOwed1
        );

        // position 已经彻底没用了，销毁
        position.tokensOwed0 = 0;
        position.tokensOwed1 = 0;

        if (position.liquidity == 0) {
            _burn(positionId);
        }
    }

    function mintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        // 检查 callback 的合约地址是否是 Pool
        (address token0, address token1, uint32 index, address payer) = abi
            .decode(data, (address, address, uint32, address));
        address _pool = poolManager.getPool(token0, token1, index);
        require(_pool == msg.sender, "Invalid callback caller");

        // 在这里给 Pool 打钱，需要用户先 approve 足够的金额，这里才会成功
        if (amount0 > 0) {
            IERC20(token0).transferFrom(payer, msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(payer, msg.sender, amount1);
        }
    }
}
