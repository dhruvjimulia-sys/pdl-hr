// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IHumanResources.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./interfaces/chainlink/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/weth/IWETH.sol";
import {CurrencyConvertUtils} from "./libraries/CurrencyConvertUtils.sol";
import {SlippageComputationUtils} from "./libraries/SlippageComputationUtils.sol";

contract HumanResources is IHumanResources {
    address private immutable hrManagerAddress;
    mapping(address => bool) private employeeActive;
    // CHECK Can only employees that were once registered withdraw?
    mapping(address => bool) private isEmployee;
    mapping(address => uint256) private weeklySalary;
    mapping(address => uint256) private employedSince;
    mapping(address => uint256) private terminatedAt;
    mapping(address => uint256) private lastWithdrawn;
    mapping(address => bool) private isEth;
    mapping(address => uint256) private accuredSalaryTillTermination;
    uint256 private activeEmployeeCount;

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

    modifier onlyHRManager() {
        require(msg.sender == hrManagerAddress, NotAuthorized());
        _;
    }

    modifier onlyActiveEmployee() {
        require(employeeActive[msg.sender], NotAuthorized());
        _;
    }

    modifier onlyEmployee() {
        require(isEmployee[msg.sender], NotAuthorized());
        _;
    }

    constructor(address _hrManagerAddress) {
        hrManagerAddress = _hrManagerAddress;
    }

    function registerEmployee(address employee, uint256 weeklyUsdSalary) external override onlyHRManager {
        require(!employeeActive[employee], EmployeeAlreadyRegistered());
        isEmployee[employee] = true;
        employeeActive[employee] = true;
        weeklySalary[employee] = weeklyUsdSalary;
        employedSince[employee] = block.timestamp;
        isEth[employee] = false;
        lastWithdrawn[employee] = block.timestamp;
        terminatedAt[employee] = 0;
        activeEmployeeCount++;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function terminateEmployee(address employee) external override onlyHRManager {
        require(employeeActive[employee], EmployeeNotRegistered());
        employeeActive[employee] = false;
        accuredSalaryTillTermination[employee] = computeAccumulatedSalary(employee);
        terminatedAt[employee] = block.timestamp;
        // CHECK employedSince semantics for terminated employees in getEmployeeInfo?
        employedSince[employee] = 0;
        activeEmployeeCount--;
        emit EmployeeTerminated(employee);
    }

    function withdrawSalary() public override onlyEmployee {
        address employee = msg.sender;
        uint256 amountInUSD = computeAccumulatedSalary(employee);
        if (amountInUSD == 0) {
            emit SalaryWithdrawn(employee, isEth[employee], 0);
            return;
        }
        uint256 amountInUSDC = CurrencyConvertUtils.convertFromUSDToUSDC(amountInUSD);
        uint256 oracleAmountInETH = CurrencyConvertUtils.convertUSDToETH(amountInUSD, ETH_USD_FEED);
        lastWithdrawn[employee] = block.timestamp;
        accuredSalaryTillTermination[employee] = 0;
        uint256 amountSent;
        if (isEth[employee]) {
            uint256 actualAmountInETH = swapUSDCForWETH(amountInUSDC, SlippageComputationUtils.slippageMinimum(oracleAmountInETH, SLIPPAGE));
            IWETH(WETH_ADDRESS).withdraw(actualAmountInETH);
            amountSent = actualAmountInETH;
            transferETH(employee, actualAmountInETH);
        } else {
            USDC.transfer(employee, amountInUSDC);
            amountSent = amountInUSDC;
        }
        emit SalaryWithdrawn(employee, isEth[employee], amountSent);
    }

    function switchCurrency() external override onlyActiveEmployee {
        address employee = msg.sender;
        withdrawSalary();
        isEth[employee] = !isEth[employee];
        emit CurrencySwitched(employee, isEth[employee]);
    }

    function salaryAvailable(address employee) external view override returns (uint256) {
        uint256 amountInUSD = computeAccumulatedSalary(employee);
        return isEth[employee] ? CurrencyConvertUtils.convertUSDToETH(amountInUSD, ETH_USD_FEED) : CurrencyConvertUtils.convertFromUSDToUSDC(amountInUSD);
    }

    function hrManager() external view override returns (address) {
        return hrManagerAddress;
    }

    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }

    function getEmployeeInfo(address employee) external view override returns (uint256, uint256, uint256) {
        return (weeklySalary[employee], employedSince[employee], terminatedAt[employee]);
    }

    function computeAccumulatedSalary(address employee) private view returns (uint256) {
        uint256 SECONDS_IN_WEEK = 7 * 24 * 3600;
        uint256 amountInUSD = (
            ((block.timestamp - lastWithdrawn[employee]) * weeklySalary[employee]) / (SECONDS_IN_WEEK)
        ) + accuredSalaryTillTermination[employee];
        return amountInUSD;
    }

    function swapUSDCForWETH(uint256 amountInUSDC, uint256 amountOutMinimum) private returns (uint256) {
        TransferHelper.safeApprove(USDC_ADDRESS, address(SWAP_ROUTER), amountInUSDC);
        uint256 amountOut = SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC_ADDRESS,
                tokenOut: WETH_ADDRESS,
                fee: UNISWAP_FEE,
                recipient: address(this),
                deadline: block.timestamp + UNISWAP_DEADLINE,
                amountIn: amountInUSDC,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
        return amountOut;
    }

    function transferETH(address recipient, uint256 amount) private {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Failed to send ETH");
    }

    // Allow the contract to receive ETH
    receive() external payable {}
}
