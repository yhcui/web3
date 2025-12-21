// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import { MEMEFactory } from "../src/MEMEFactory.sol";

contract CounterTest is Test {

    function setUp() public {
    }

    function test_Deploy() public {
        MEMEFactory factory = new MEMEFactory(address(this));
        assertEq(factory.MEME(), address(0));
    }
}
