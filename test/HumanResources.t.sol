// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../src/IHumanResources.sol";

import {CurrencyConvertUtils} from "../src/libraries/CurrencyConvertUtils.sol";
import {SlippageComputationUtils} from "../src/libraries/SlippageComputationUtils.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../src/interfaces/chainlink/AggregatorV3Interface.sol";
import "../src/interfaces/weth/IWETH.sol";

// TODO CHECK FOR EVENTS
// TODO CHECK SALARY ACCRUAL FOR LESS THAN WEEK, MORE THAN WEEK
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

    uint24 private constant UNISWAP_FEE = 3000;
    uint256 private constant UNISWAP_DEADLINE = 30;
    uint256 private constant SLIPPAGE = 2;

    function setUp() public {
        // TODO Replace with optimism fork??
        uint256 optimismFork = vm.createFork("https://optimism-mainnet.infura.io/v3/8a6b3b58c4ec4de19ff4e06e74a593c5");
        vm.selectFork(optimismFork);

        hrManager = makeAddr("hrManager");
        employee1 = makeAddr("employee1");
        employee2 = makeAddr("employee2");
        hr = new HumanResources(hrManager);
    }

    function testConstructor() public view {
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

        assertEq(hr.salaryAvailable(employee1), convertFromUSDToUSDC(WEEKLY_SALARY));
    }

    function testWithdrawSalary() public {
        supplyUSDCToHR(WEEKLY_SALARY);

        vm.startPrank(hrManager);
        hr.registerEmployee(employee1, WEEKLY_SALARY);
        vm.stopPrank();

        // Fast forward 1 week
        vm.warp(block.timestamp + SECONDS_IN_WEEK);

        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
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
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);

        vm.startPrank(employee1);
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
        hr.switchCurrency(); // Switch to ETH
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInETH = hr.salaryAvailable(employee1);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(WEEKLY_SALARY, ETH_USD_FEED);
        assertEq(amountInETH, oracleAmountInETH);

        vm.startPrank(employee1);
        hr.withdrawSalary(); // Withdraw ETH
        assertEq(hr.salaryAvailable(employee1), 0);
        assertGe(employee1.balance, SlippageComputationUtils.slippageMinimum(oracleAmountInETH, SLIPPAGE));
        vm.stopPrank();

        // Switch back to USDC
        vm.startPrank(employee1);
        hr.switchCurrency();
        vm.stopPrank();

        vm.warp(block.timestamp + SECONDS_IN_WEEK);
        uint256 amountInUsdc = hr.salaryAvailable(employee1);
        assertEq(amountInUsdc, convertFromUSDToUSDC(WEEKLY_SALARY));

        vm.startPrank(employee1);
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
        // TODO What happens if we dont send ETH? What if we instead use WETH?
        SWAP_ROUTER.exactOutputSingle{value: amountInETHMaximum}(params);
    }

    function supplyUSDCToHR(uint256 amountInUSD) private {
        uint256 amountInETH = CurrencyConvertUtils.convertUSDToETH(amountInUSD, ETH_USD_FEED);
        uint256 slippageAmount = SlippageComputationUtils.slippageMaximum(amountInETH, SLIPPAGE);
        vm.deal(address(this), slippageAmount);
        swapETHForUSDC(convertFromUSDToUSDC(amountInUSD), slippageAmount, address(hr));
    }

    // TODO Abstract this to a library
    function convertFromUSDToUSDC(uint256 amountInUSD) private pure returns (uint256) {
        uint256 USD_TO_USDC = 1e12;
        return amountInUSD / USD_TO_USDC;
    }
}
