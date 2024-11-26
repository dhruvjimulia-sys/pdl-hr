// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../src/IHumanResources.sol";

import {CurrencyConvertUtils} from "../src/libraries/CurrencyConvertUtils.sol";
import {SlippageComputationUtils} from "../src/libraries/SlippageComputationUtils.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../src/interfaces/chainlink/AggregatorV3Interface.sol";
import "../src/interfaces/weth/IWETH.sol";

contract ExhaustiveHumanResourcesTest is Test {
    IHumanResources hr;
    address hrManager;
    address employee1;
    address employee2;

    uint256 private constant SECONDS_IN_WEEK = 7 * 24 * 3600;
    uint256 private constant SECONDS_IN_DAY = 24 * 3600;

    uint256 private constant WEEKLY_SALARY = 1000e18;
    uint256 private constant ANOTHER_WEEKLY_SALARY = 3456e18;

    address private constant USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    IERC20 private constant USDC = IERC20(USDC_ADDRESS);

    address private constant CHAINLINK_ETH_USD_FEED = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    AggregatorV3Interface private constant ETH_USD_FEED = AggregatorV3Interface(CHAINLINK_ETH_USD_FEED);

    address private constant UNISWAP_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter private constant SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);

    address private constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    uint24 private constant UNISWAP_FEE = 500;
    uint256 private constant UNISWAP_DEADLINE = 30;
    uint256 private constant SLIPPAGE = 2;
    
    function setUp() public {
        uint256 optimismFork = vm.createFork("https://mainnet.optimism.io");
        vm.selectFork(optimismFork);

        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2");

        vm.startPrank(hrManager);
        hr = new HumanResources();
        vm.stopPrank();
    }

    function testRegisterEmployee() public {
        vm.startPrank(hrManager);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.EmployeeRegistered(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();
    }

    function testUnregisteredEmployeeCannotRegisterEmployees() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();
    }

    function testActiveEmployeeNotHRManagerCannotRegisterEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        vm.stopPrank();
    }

    function testTerminatedEmployeeCannotRegisterEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
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
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.EmployeeTerminated(employee1);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testUnregisteredNonTerminatedEmployeeCannotTerminateEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.terminateEmployee(employee2);
        vm.stopPrank();
    }

    function testActiveEmployeeNotHRManagerCannotTerminateEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.terminateEmployee(employee2);
        vm.stopPrank();
    }

    function testTerminatedEmployeeCannotTerminateEmployees() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee2, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.terminateEmployee(employee2);
        vm.stopPrank();
    }

    function testTerminateUnregisteredEmployee() public {
        vm.startPrank(hrManager);
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testTerminateAlreadyTerminatedEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testSalaryAccumulationOneSecondAtATime() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY / SECONDS_IN_WEEK));
        vm.warp(block.timestamp + 1);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC((WEEKLY_SALARY * 2) / SECONDS_IN_WEEK));
        vm.warp(block.timestamp + 1);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC((WEEKLY_SALARY * 3) / SECONDS_IN_WEEK));
    }

    function testSalaryAccumulationOneDayAtATime() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_DAY);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY / 7));
        vm.warp(block.timestamp + SECONDS_IN_DAY);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC((2 * WEEKLY_SALARY) / 7));
        vm.warp(block.timestamp + SECONDS_IN_DAY);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC((3 * WEEKLY_SALARY) / 7));
    }

    function testSalaryAccumulationOneWeekAtATime() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 2));
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 3));
    }

    function testSalaryAccumulationWithAnotherWeeklySalary() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, ANOTHER_WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(ANOTHER_WEEKLY_SALARY));
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(ANOTHER_WEEKLY_SALARY * 2));
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(ANOTHER_WEEKLY_SALARY * 3));
    }

    function testSalaryAccumulationStopsWhenEmployeeIsTerminated() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));
    }

    function testSalaryAccumulationTerminatedThenReRegistered() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        hr.terminateEmployee(employee1);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 2));

        hr.terminateEmployee(employee1);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 2));

        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 3));
        vm.stopPrank();
    }

    function testSwitchCurrency() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.CurrencySwitched(employee1, true);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);
    }

    function testSwitchCurrencyTwiceAndWithdraw() public {
        supplyUSDCToHR(WEEKLY_SALARY * 2);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.CurrencySwitched(employee1, true);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, false);
        emit IHumanResources.SalaryWithdrawn(employee1, true, oracleAmountInETH);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertGe(employee1.balance, SlippageComputationUtils.slippageMinimum(oracleAmountInETH, SLIPPAGE));
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.CurrencySwitched(employee1, false);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.SalaryWithdrawn(employee1, false, amountInUsdc);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
        vm.stopPrank();
    }

    function testSwitchCurrencyAutomaticallyWithdrawsSalary() public {
        supplyUSDCToHR(WEEKLY_SALARY);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.SalaryWithdrawn(employee1, false, amountInUsdc);
        hr.switchCurrency();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
        vm.stopPrank();
    }

    function testSwitchCurrencyUnregisteredEmployee() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.switchCurrency();
        vm.stopPrank();
    }

    function testSwitchCurrencyTerminatedEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.switchCurrency();
        vm.stopPrank();
    }

    function testSwitchCurrencyReregisteredEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.CurrencySwitched(employee1, true);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);
    }

    function testWithdrawEmptySalary() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        
        hr.withdrawSalary();
        vm.stopPrank();
    }

    function testWithdrawSalaryInUSDC() public {
        supplyUSDCToHR(WEEKLY_SALARY);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.SalaryWithdrawn(employee1, false, amountInUsdc);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
        vm.stopPrank();
    }

    function testWithdrawSalaryInETH() public {
        supplyUSDCToHR(WEEKLY_SALARY);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, false);
        emit IHumanResources.SalaryWithdrawn(employee1, true, oracleAmountInETH);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertGe(employee1.balance, SlippageComputationUtils.slippageMinimum(oracleAmountInETH, SLIPPAGE));
        vm.stopPrank();
    }

    function testUnregisteredEmployeeCannotWithdrawSalary() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.withdrawSalary();
        vm.stopPrank();
    }

    function testWithdrawSalaryTerminatedEmployee() public {
        supplyUSDCToHR(WEEKLY_SALARY);
        
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.SalaryWithdrawn(employee1, false, amountInUsdc);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
        vm.stopPrank();
    }

    function testWithdrawSalaryReregisteredEmployee() public {
        supplyUSDCToHR(WEEKLY_SALARY * 2);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY * 2));

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.SalaryWithdrawn(employee1, false, amountInUsdc);
        hr.withdrawSalary();
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
        vm.stopPrank();
    }

    function testSalaryAvailableAndThatDefaultSalaryIsUSDC() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        assertEq(hr.salaryAvailable(employee1), 0);
        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));
    }

    function testHRManager() public view {
        assertEq(hr.hrManager(), hrManager);
    }

    function testGetActiveEmployeeCount() public {
        vm.startPrank(hrManager);
        assertEq(hr.getActiveEmployeeCount(), 0);

        hr.registerEmployee(employee1, WEEKLY_SALARY);
        assertEq(hr.getActiveEmployeeCount(), 1);

        hr.registerEmployee(employee2, WEEKLY_SALARY);
        assertEq(hr.getActiveEmployeeCount(), 2);

        hr.terminateEmployee(employee1);
        assertEq(hr.getActiveEmployeeCount(), 1);

        hr.terminateEmployee(employee2);
        assertEq(hr.getActiveEmployeeCount(), 0);
        vm.stopPrank();
    }

    function testGetEmployeeInfoUnregisteredEmployee() view public {
        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = hr.getEmployeeInfo(employee1);
        assertEq(salary, 0);
        assertEq(employedSince, 0);
        assertEq(terminatedAt, 0);
    }

    function testGetEmployeeInfoRegisteredEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        uint256 registrationTimestamp = block.timestamp;
        vm.warp(registrationTimestamp + SECONDS_IN_WEEK);

        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(employedSince, registrationTimestamp);
        assertEq(terminatedAt, 0);
    }

    function testGetEmployeeInfoTerminatedEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        uint256 registrationTimestamp = block.timestamp;
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        uint256 terminationTimestamp = block.timestamp;
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(employedSince, registrationTimestamp);
        assertEq(terminatedAt, terminationTimestamp);
    }

    function testGetEmployeeInfoReregisteredEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.terminateEmployee(employee1);
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY * 2);
        uint256 registrationTimestamp = block.timestamp;
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY * 2);
        assertEq(employedSince, registrationTimestamp);
        assertEq(terminatedAt, 0);
    }

    function swapETHForUSDC(uint256 amountInUSDC, uint256 amountInETHMaximum, address recipient) private {
        TransferHelper.safeApprove(WETH_ADDRESS, address(SWAP_ROUTER), amountInETHMaximum);
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: USDC_ADDRESS,
            fee: UNISWAP_FEE,
            recipient: recipient,
            deadline: block.timestamp + UNISWAP_DEADLINE,
            amountInMaximum: amountInETHMaximum,
            amountOut: amountInUSDC,
            sqrtPriceLimitX96: 0
        });
        IWETH(WETH_ADDRESS).deposit{value: amountInETHMaximum}();
        SWAP_ROUTER.exactOutputSingle(params);
    }

    function supplyUSDCToHR(uint256 amountInUSD) private {
        uint256 amountInETH = CurrencyConvertUtils.convertUSDToETH(amountInUSD, ETH_USD_FEED);
        uint256 slippageAmount = SlippageComputationUtils.slippageMaximum(amountInETH, SLIPPAGE);
        vm.deal(address(this), slippageAmount);
        swapETHForUSDC(CurrencyConvertUtils.convertFromUSDToUSDC(amountInUSD), slippageAmount, address(hr));
    }
}
