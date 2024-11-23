// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../src/IHumanResources.sol";

contract HumanResourcesTest is Test {
    HumanResources hr;
    address hrManager;
    address employee1;
    address employee2;
    uint256 constant WEEKLY_SALARY = 1000e18;
    uint256 constant WEEKLY_SALARY_IN_USDC = 1000e6;
    uint256 constant SECONDS_IN_WEEK = 7 * 24 * 3600;
 
    function setUp() public {
        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2"); 
        hr = new HumanResources(hrManager);
    }

    function testConstructor() view public {
        assertEq(hr.hrManager(), hrManager);
        assertEq(hr.getActiveEmployeeCount(), 0);
    }

    function testRegisterEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        assertEq(hr.getActiveEmployeeCount(), 1);
        (uint256 salary, uint256 since, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(since, block.timestamp);
        assertEq(terminated, 0);
    }

    function testRegisterEmployeeNotHRManager() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();
    }

    function testRegisterEmployeeTwice() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();
    }

    function testTerminateEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        assertEq(hr.getActiveEmployeeCount(), 0);
        (,, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(terminated, block.timestamp);
    }

    function testTerminateEmployeeNotHRManager() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testTerminateNonExistentEmployee() public {
        vm.startPrank(hrManager);
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testSalaryAccumulation() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        // Fast forward 1 week
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        
        assertEq(hr.salaryAvailable(employee1), WEEKLY_SALARY_IN_USDC);
    }

    function testWithdrawSalary() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        // Fast forward 1 week
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        
        vm.startPrank(employee1);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        vm.stopPrank();
    }

    function testSwitchCurrency() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        hr.switchCurrency();
        vm.stopPrank();

        // Test that next salary will be in ETH
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), 0); // ETH conversion not implemented yet
    }

    function testSwitchCurrencyNotEmployee() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.switchCurrency();
        vm.stopPrank();
    }

    function testMultipleEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee2, WEEKLY_SALARY * 2);
        vm.stopPrank();

        assertEq(hr.getActiveEmployeeCount(), 2);
        
        (uint256 salary1,,) = hr.getEmployeeInfo(employee1);
        (uint256 salary2,,) = hr.getEmployeeInfo(employee2);
        
        assertEq(salary1, WEEKLY_SALARY);
        assertEq(salary2, WEEKLY_SALARY * 2);
    }
}