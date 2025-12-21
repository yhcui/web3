// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import { IMEMEFactory } from "./interfaces/IMEMEFactory.sol";
import { MEMEToken } from "./MEMEToken.sol";

/**
 * @title MEMEFactory
 * @dev Factory contract for deploying XXXToken contracts using CREATE2
 */
contract MEMEFactory is IMEMEFactory, AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    address public MEME;
    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @dev Deploy a new MEMEToken contract using CREATE2
     * @param name Token name
     * @param symbol Token symbol
     * @param totalSupply Total token supply
     * @param timestamp Deployment timestamp for salt generation
     * @param nonce Nonce for salt generation
     * @return Address of the deployed token contract
     */
    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 timestamp,
        uint256 nonce
    ) external onlyRole(DEPLOYER_ROLE) returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, XXX, timestamp, nonce));
        XXXToken token = new XXXToken{salt: salt}(name, symbol, totalSupply, XXX);
        emit TokenDeployed(address(token), name, symbol, totalSupply, msg.sender);
        return address(token);
    }

    /**
     * @dev Predict the address of a token that would be deployed with given parameters
     * @param name Token name
     * @param symbol Token symbol
     * @param totalSupply Total token supply
     * @param owner Owner address of the token
     * @param timestamp Deployment timestamp for salt generation
     * @param nonce Nonce for salt generation
     * @return Predicted token contract address
     */
    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address owner,
        uint256 timestamp,
        uint256 nonce
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, owner, timestamp, nonce));

        // Calculate CREATE2 address
        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(XXXToken).creationCode,
                abi.encode(name, symbol, totalSupply, owner)
            ))
        ));

        return address(uint160(uint256(hash)));
    }

    function setXXX(address _XXX) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_XXX != address(0), "ZeroAddress");
        _grantRole(DEPLOYER_ROLE, _XXX);
        XXX = _XXX;
    }
} 