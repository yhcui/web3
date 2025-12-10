pragma solidity =0.6.6;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Migrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
import './interfaces/V1/IUniswapV1Exchange.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';

contract UniswapV2Migrator is IUniswapV2Migrator {
    // Uniswap V1工厂合约实例
    IUniswapV1Factory immutable factoryV1;
    // Uniswap V2路由器合约实例
    IUniswapV2Router01 immutable router;

    /**
     * @dev 构造函数，初始化V1工厂和V2路由器地址
     * @param _factoryV1 V1版本的工厂合约地址
     * @param _router V2版本的路由器合约地址
     */
    constructor(address _factoryV1, address _router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        router = IUniswapV2Router01(_router);
    }

    // 接收ETH转账的回调函数，需要接收来自任何V1交易所和路由器的ETH
    // 理想情况下这应该被强制执行，就像在路由器中一样，
    // 但由于需要调用V1工厂，消耗gas过多而无法实现
    receive() external payable {}

    /**
     * @dev 将流动性从V1迁移到V2
     * @param token 代币地址
     * @param amountTokenMin 最小期望获得的代币数量
     * @param amountETHMin 最小期望获得的ETH数量
     * @param to 流动性接收者地址
     * @param deadline 交易截止时间戳
     */
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
        override
    {
        /**
         正确的资金流向：在 migrate 函数执行过程中：
            1、用户的 V1 流动性被提取并发送到此合约
            2、部分代币用于添加到 V2 流动性池
            3、剩余代币通过 safeTransfer 直接返还给用户
         */
        // 获取V1版本的交易所合约
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(token));
        // 查询发送者在V1交易所中的流动性余额
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        // 将流动性从发送者转移至当前合约
        // 用户需要先手动授权（approve）V1 交易所合约可以操作自己的流动性代币，这是在调用 migrate 函数之前由用户完成的操作
        // 在调用 migrate 函数之前，用户必须手动授权（approve）V1 交易所合约可以操作他们的流动性代币。这是一个需要用户单独执行的前置交易操作。
        // 前提条件：在调用 migrate 函数之前，用户必须手动授权（approve）V1 交易所合约可以操作他们的流动性代币。这是一个需要用户单独执行的前置交易操作。 
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        // 移除V1版本的流动性，获得ETH和代币
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        // 授权路由器可以使用代币
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        // 在V2版本中添加流动性，使用ETH和代币创建交易对
        
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );

        /*
         addLiquidityETH 函数的设计保证了只会完全使用 amountETHV1 或 amountTokenV1 中的一个约束条件
         这意味着要么所有 ETH 被使用完（可能有代币剩余），要么所有代币被使用完（可能有 ETH 剩余）
        */
        // 如果实际使用的代币少于提取的代币数量，则退还多余的代币给发送者
        if (amountTokenV1 > amountTokenV2) {
            TransferHelper.safeApprove(token, address(router), 0); // 成为良好的区块链公民，重置授权额度为0
            // 这里的 safeTransfer 是将代币从 UniswapV2Migrator 合约直接转账给 msg.sender，而不是代表某个账户消费代币。这是普通的转账操作，不需要预先批准。
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH保证会使用全部amountETHV1或amountTokenV1，因此这个else分支是安全的
            // 如果实际使用的ETH少于提取的ETH数量，则退还多余的ETH给发送者
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}