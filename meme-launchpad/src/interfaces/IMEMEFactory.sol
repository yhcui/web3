// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMEMEFactory {
    error UnauthorizedDeployer();

    event TokenDeployed(
        address indexed token,
        string name,
        string symbol,
        uint256 totalSupply,
        address indexed deployer
    );

    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 timestamp,  
        uint256 nonce
    ) external returns (address);

    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address owner,
        uint256 timestamp,
        uint256 nonce
    ) external view returns (address);
} 