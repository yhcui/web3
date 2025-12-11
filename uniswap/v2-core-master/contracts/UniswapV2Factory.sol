// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

// Uniswap V2 工厂合约，负责创建交易对并管理协议费用
contract UniswapV2Factory is IUniswapV2Factory {
    // 协议费用接收地址
    address public feeTo;
    // 协议费用设置者地址
    address public feeToSetter;

    // 交易对映射：token0 => token1 => pairAddress
    mapping(address => mapping(address => address)) public getPair;
    // 所有交易对地址数组
    address[] public allPairs;

    // 创建交易对事件
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // 构造函数，设置协议费用设置者
    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    // 获取所有交易对数量
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // 创建新的交易对
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // 确保不是相同地址
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        // 对代币地址排序，确保token0 < token1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 确保不是零地址
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        // 确保交易对不存在
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // 单次检查就足够了
        // 获取UniswapV2Pair合约的创建字节码
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        // 使用token0和token1生成salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // 使用create2部署新的交易对合约
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // 初始化新创建的交易对
        IUniswapV2Pair(pair).initialize(token0, token1);
        // 在映射中记录交易对地址
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // 反向也记录映射
        // 添加到所有交易对数组
        allPairs.push(pair);
        // 触发交易对创建事件
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // 设置协议费用接收地址
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    // 设置协议费用设置者地址
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}