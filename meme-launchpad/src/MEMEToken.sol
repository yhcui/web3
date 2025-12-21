// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
/**
 * @title XXXToken
 * @dev Custom ERC20 token with transfer restrictions for XXX platform
 */
contract MEMEToken is ERC20Burnable {
    enum TransferMode {
        MODE_NORMAL,              // 0: Normal mode (after graduation)
        MODE_TRANSFER_RESTRICTED, // 1: Transfer prohibited (initial state)
        MODE_TRANSFER_CONTROLLED
    }

    TransferMode public transferMode;
    address public vestingContract;
    address public pair;
    address public XXXCore;

    error TransferRestricted();
    error TransferToTokenNotAllowed();
    error TransferNotAllowedToPair();
    error TransferNotAllowed();
    error onlyXXXCall();
    error ZeroAddress();

    event TransferModeChanged(TransferMode oldMode, TransferMode newMode);
    event VestingContractChanged(address vestingContract);
    event PairChanged(address pair);

    modifier onlyXXX() {
        if (msg.sender != XXXCore) revert onlyXXXCall();
        _;
    }
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address _XXX
    ) ERC20(name, symbol)  {
        if (_XXX == address(0)) revert ZeroAddress();
        transferMode = TransferMode.MODE_TRANSFER_RESTRICTED;
        if (totalSupply > 0) {
            _mint(_XXX, totalSupply);
        }
        XXXCore = _XXX;
    }

    /**
     * @dev Set transfer mode for the token
     * @param _mode New transfer mode
     */
    function setTransferMode(TransferMode _mode) external onlyXXX {
        TransferMode oldMode = transferMode;
        transferMode = _mode;
        emit TransferModeChanged(oldMode, _mode);
    }

    /**
     * @dev Set vesting contract address
     * @param _vestingContract Vesting contract address
     */
    function setVestingContract(address _vestingContract) external onlyXXX {
        if (_vestingContract == address(0)) revert ZeroAddress();
        vestingContract = _vestingContract;
        emit VestingContractChanged(_vestingContract);

    }

    /**
     * @dev Set PancakeSwap pair address
     * @param _pair Pair contract address
     */
    function setPair(address _pair) external onlyXXX {
        if (_pair == address(0)) revert ZeroAddress();
        pair = _pair;
        emit PairChanged(_pair);

    }

    /**
     * @dev Hook called before any token transfer
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        // Allow mint (from == address(0)) and burn (to == address(0)) operations
        if (from == address(0) || to == address(0)) {
            return;
        }

        if (to == address(this)) {
            revert TransferToTokenNotAllowed();
        }

        if (from == vestingContract && vestingContract != address(0)) {
            return;
        }

        // Block transfers to pair when not in normal mode
        if (transferMode != TransferMode.MODE_NORMAL && to == pair && pair != address(0)) {
            revert TransferNotAllowedToPair(); // or a more specific error
        }

        if (transferMode == TransferMode.MODE_TRANSFER_RESTRICTED) {
            revert TransferRestricted();
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        _beforeTokenTransfer(from, to, value);
        super._update(from, to, value);
    }
} 