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

// TODO CHECK SALARY ACCRUAL FOR ONE SECOND, MORE THAN WEEK
// TODO OTHER TESTS AND EDGE CASES
// TODO WITHDRAW EMPTY SALARY
// WAIT AFTER REGISTERING TO TEST FOR GETEMPLOYEEINFO
// TEST FOR REREGISTRATION EDGE CASE
contract HumanResourcesTest is Test {
    HumanResources hr;
    address hrManager;
    address employee1;
    address employee2;

    uint256 private constant WEEKLY_SALARY = 1000e18;
    uint256 private constant SECONDS_IN_WEEK = 7 * 24 * 3600;

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

    // CHECK is it necessary to set the block number -> tests also check oracle rather than using constant values?
    uint256 private constant FORK_TESTING_BLOCK_NUMBER = 128468945;

    function setUp() public {
        // TODO Replace with optimism fork?
        uint256 optimismFork = vm.createFork("https://optimism-mainnet.infura.io/v3/8a6b3b58c4ec4de19ff4e06e74a593c5", FORK_TESTING_BLOCK_NUMBER);
        vm.selectFork(optimismFork);

        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2");

        vm.startPrank(hrManager);
        hr = new HumanResources();
        vm.stopPrank();
    }

    function testHRManager() public view {
        assertEq(hr.hrManager(), hrManager);
    }

    function testRegisterEmployee() public {
        vm.startPrank(hrManager);
        vm.expectEmit(true, true, true, true);
        emit IHumanResources.EmployeeRegistered(employee1, WEEKLY_SALARY);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        assertEq(hr.getActiveEmployeeCount(), 1);
        (uint256 salary, uint256 since, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(salary, WEEKLY_SALARY);
        assertEq(since, block.timestamp);
        assertEq(terminated, 0);
    }

    function testUnregisteredNonTerminatedEmployeeCannotRegisterEmployees() public {
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

        assertEq(hr.getActiveEmployeeCount(), 0);
        (,, uint256 terminated) = hr.getEmployeeInfo(employee1);
        assertEq(terminated, block.timestamp);
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

    function testTerminateUnregisteredNonTerminatedEmployee() public {
        vm.startPrank(hrManager);
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        hr.terminateEmployee(employee1);
        vm.stopPrank();
    }

    function testTerminateTerminatedEmployee() public {
        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        hr.terminateEmployee(employee1);
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

        assertEq(hr.salaryAvailable(employee1), CurrencyConvertUtils.convertFromUSDToUSDC(WEEKLY_SALARY));
    }

    function testWithdrawSalary() public {
        supplyUSDCToHR(WEEKLY_SALARY);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        // Fast forward 1 week
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

    function testSwitchCurrencyAndWithdrawETH() public {
        supplyUSDCToHR(WEEKLY_SALARY);

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
    }

    function testSwitchCurrencyNotEmployee() public {
        vm.startPrank(employee1);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        hr.switchCurrency();
        vm.stopPrank();
    }

    function testSwitchCurrencyTwiceAndWithdraw() public {
        supplyUSDCToHR(WEEKLY_SALARY * 2);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, false);
        emit IHumanResources.CurrencySwitched(employee1, true);
        hr.switchCurrency(); // Switch to ETH
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);

        vm.startPrank(employee1);
        vm.expectEmit(true, true, true, false);
        emit IHumanResources.SalaryWithdrawn(employee1, true, oracleAmountInETH);
        hr.withdrawSalary(); // Withdraw ETH
        assertEq(hr.salaryAvailable(employee1), 0);
        assertGe(employee1.balance, SlippageComputationUtils.slippageMinimum(oracleAmountInETH, SLIPPAGE));
        vm.stopPrank();

        // Switch back to USDC
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
        hr.withdrawSalary(); // Withdraw USDC
        assertEq(hr.salaryAvailable(employee1), 0);
        assertEq(USDC.balanceOf(employee1), amountInUsdc);
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
