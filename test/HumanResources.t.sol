// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../src/IHumanResources.sol";

contract HumanResourcesTest is Test {
    IHumanResources public humanResources;

    function setUp() public {
        humanResources = new HumanResources();
    }
}