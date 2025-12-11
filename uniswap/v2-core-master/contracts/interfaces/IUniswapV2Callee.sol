pragma solidity >=0.5.0;

/**
 * @title IUniswapV2Callee
 * @dev Uniswap V2 Pair 在执行 swap/flash 操作并向接收方发送 token 后，会回调实现此接口的合约。
 *      回调允许接收方（通常是一个合约）在收到 token 后立即执行自定义逻辑（例如使用收到的资金进行 arbitrage、调用其他合约然后偿还借款等）。
 *
 * 说明：这是一个非常小的接口，仅包含一个回调函数 `uniswapV2Call`。
 * 当 Pair 在 `swap` 中发送 token 给某个合约并且附带 data 参数时，
 * Pair 会在转账后调用接收合约的 `uniswapV2Call`，把执行控制权交给接收合约以完成后续操作。
 */
interface IUniswapV2Callee {
    /**
     * @notice 回调函数，由 `UniswapV2Pair` 在 swap/flash 操作后调用
     * @param sender 发起调用并触发这次回调的地址（通常是调用 `swap` 的合约地址或用户地址）
     * @param amount0 此次由 Pair 发送的 token0 数量（可能为 0）
     * @param amount1 此次由 Pair 发送的 token1 数量（可能为 0）
     * @param data 任意字节数组，调用方在 `swap` 时传入，回调合约可以解析并据此执行逻辑
     *
     * 注意：实现合约在回调中必须完成所需的逻辑并在返回前确保按照 Pair 的要求（例如偿还借款+手续费）完成必要的转账。
     * 若未按协议要求处理，Pair 合约可能会导致交易回退。
     */
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
