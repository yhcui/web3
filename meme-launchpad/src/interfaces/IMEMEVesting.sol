// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVestingParams} from "./IVestingParams.sol";

interface IMEMEVesting is IVestingParams {
    // Error definitions
    error InvalidParameters();
    error InvalidAddressParameters();
    error InvalidLengthParameters();
    error InvalidAmountParameters();
    error NoClaimableAmount();
    error ScheduleNotFound();
    error ScheduleRevoked();
    error InsufficientBalance();
    error Unauthorized();
    error InvalidPercentage();
    /**
     * @dev Vesting schedule structure for linear release
     */
    struct VestingSchedule {
        uint256 totalAmount;        // Total amount of tokens locked
        uint256 startTime;          // Vesting start time (creation time)
        uint256 endTime;            // Vesting end time (unlock time)
        uint256 claimedAmount;      // Amount already claimed
        bool revoked;               // Whether the schedule has been revoked
        VestingMode mode;
    }

    // Events
    event VestingScheduleCreated(
        address indexed token,
        address indexed beneficiary,
        uint256 scheduleId,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event TokensClaimed(
        address indexed token,
        address indexed beneficiary,
        uint256 scheduleId,
        uint256 amount
    );

    event VestingScheduleRevoked(
        address indexed token,
        address indexed beneficiary,
        uint256 scheduleId,
        uint256 remainingAmount
    );

    event EmergencyWithdraw(
        address indexed token,
        address indexed beneficiary,
        uint256 amount
    );

    // Functions
    function createVestingSchedules(address token, address beneficiary, VestingAllocation[] calldata allocations) external returns (uint256[] memory scheduleIds);

    function claim(address token, uint256 scheduleId) external returns (uint256 claimableAmount);

    function claimAll(address token) external returns (uint256 totalClaimed);

    function getVestingSchedule(address token, address beneficiary, uint256 scheduleId) external view returns (VestingSchedule memory);

    function getVestingScheduleCount(address token, address beneficiary) external view returns (uint256);

    function getClaimableAmount(address token, address beneficiary, uint256 scheduleId) external view returns (uint256);

    function getTotalClaimableAmount(address token, address beneficiary) external view returns (uint256);

    function getTotalVestedAmount(address token, address beneficiary) external view returns (uint256 vested, uint256 claimed, uint256 locked);

    function revokeVestingSchedule(address token, address beneficiary, uint256 scheduleId) external;

    function emergencyWithdrawToken(address token, uint256 amount) external;
}