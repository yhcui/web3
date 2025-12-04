// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
/**
 * 它是一个基于 OpenZeppelin ERC721 标准的高级 NFT 铸造系统，集成了动态铸造权限（白名单/指定铸造者）、防女巫攻击（限制每地址铸造量）、动态元数据以及基本的付费铸造和资金提取功能。
 * 功能
 * 1. 权限管理: Merkle Tree 白名单 + 独立 Minter 列表。
 * 2. 防女巫攻击: 限制每个地址的最大铸造数量。
 * 3. 动态元数据: 支持设置基础 URI 和针对每个 Token 设置独立属性。
 * 4. 付费铸造: 要求支付一定数量的 Ether。
 * @title 
 * @author 
 * @notice 
 */
contract AdvancedMintingSystem is ERC721, Ownable {

    // 安全的 ID 计数器
    using Counters for Counters.Counter;
    
    // 代币计数器 -- 用于安全地生成下一个可用的 Token ID
    Counters.Counter private _tokenIdCounter;
    
    // 动态铸造权限相关 -- 独立维护一个指定铸造者的白名单
    mapping(address => bool) private _minters;

    // Merkle Tree 白名单的根哈希，用于批量地址的白名单验证
    bytes32 public merkleRoot; // 用于白名单验证
    
    // 防女巫攻击-- 记录每个地址已铸造的 Token 数量，用于防女巫攻击。
    mapping(address => uint256) private _mintedCount;

    // 每个地址允许铸造的最大数量，默认为 1
    uint256 public maxMintPerAddress = 1;
    
    // 元数据动态生成 - 基础元数据 URI（例如 ipfs://.../）。
    string private _baseTokenURI;

    // 存储每个 Token ID 独特的、自定义的属性字符串，用于动态元数据。
    mapping(uint256 => string) private _tokenAttributes;
    
    // 铸造价格 - 铸造 NFT 所需的 Ether 价格，默认为0.05 ether
    uint256 public mintPrice = 0.05 ether;
    
    // 事件
    event MintPermissionUpdated(address indexed minter, bool allowed);
    event MerkleRootUpdated(bytes32 newRoot);
    event MetadataUpdated(uint256 tokenId, string attributes);
    
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}
    
    // ========== 动态铸造权限管理 ==========
    
    // 设置Merkle Root用于白名单验证
    // 值通常由 项目方（NFT 合约所有者） 在链下计算
    function setMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
        emit MerkleRootUpdated(root);
    }
    
    // 添加/移除铸造权限
    function setMinter(address minter, bool allowed) external onlyOwner {
        _minters[minter] = allowed;
        emit MintPermissionUpdated(minter, allowed);
    }
    
    // 验证铸造权限
    // 获取 proof 和 merkleRoot 是使用 Merkle Tree 白名单机制的核心步骤。它们分别在链下（计算 proof 和 merkleRoot）和链上（验证 proof）起作用。
    modifier onlyMinter(bytes32[] calldata proof) {
        // keccak256(abi.encodePacked(msg.sender)) 将调用者的地址哈希作为叶子节点进行验证。
        require(
            _minters[msg.sender] || 
            MerkleProof.verify(proof, merkleRoot, keccak256(abi.encodePacked(msg.sender))),
            "Caller is not allowed to mint"
        );
        _;
    }
    
    // ========== 防女巫攻击 ==========
    
    // 设置每个地址最大铸造量
    function setMaxMintPerAddress(uint256 max) external onlyOwner {
        maxMintPerAddress = max;
    }
    
    // 检查是否超过最大铸造量
    modifier checkMintLimit() {
        require(
            _mintedCount[msg.sender] < maxMintPerAddress,
            "Exceeds maximum mint limit per address"
        );
        _;
        _mintedCount[msg.sender]++;
    }
    
    // ========== 元数据动态生成 ==========
    
    // 设置基础URI
    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }
    
    // 设置代币属性(可扩展为链上或链下生成)
    function setTokenAttributes(uint256 tokenId, string calldata attributes) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner nor approved");
        _tokenAttributes[tokenId] = attributes;
        emit MetadataUpdated(tokenId, attributes);
    }
    
    // 重写tokenURI方法实现动态元数据 
    // 它根据 tokenId 返回完整的元数据 URI。如果 _tokenAttributes 中有自定义属性，它会将其作为查询参数拼接在 URI 后面
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        string memory baseURI = _baseURI();
        string memory attributes = _tokenAttributes[tokenId];
        
        if(bytes(attributes).length > 0) {
            return string(abi.encodePacked(baseURI, Strings.toString(tokenId), "?attributes=", attributes));
        }
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId)));
    }
    
    // ========== 铸造功能 ==========
    
    // 公开铸造函数
    function mint(bytes32[] calldata proof, string calldata initialAttributes) 
        external 
        payable 
        onlyMinter(proof)
        checkMintLimit
    {
        require(msg.value >= mintPrice, "Insufficient payment");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(msg.sender, tokenId);
        
        if(bytes(initialAttributes).length > 0) {
            _tokenAttributes[tokenId] = initialAttributes;
        }
    }
    
    // 提取资金
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}