// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVestingParams {
    enum VestingMode {
        BURN,
        CLIFF,
        LINEAR
    }
    struct VestingAllocation {
        uint256 amount;
        uint256 launchTime;
        uint256 duration;
        VestingMode mode;
    }
} 