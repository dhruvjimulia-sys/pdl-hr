// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IHumanResources.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/chainlink/interfaces/AggregatorV3Interface.sol";
import "uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";


contract HumanResources is IHumanResources {

    address immutable private hrManagerAddress;
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
    
    address constant USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    IERC20 constant USDC = IERC20(USDC_ADDRESS);

    address constant CHAINLINK_ETH_USD_FEED = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    AggregatorV3Interface constant ETH_USD_FEED = AggregatorV3Interface(CHAINLINK_ETH_USD_FEED);

    address constant UNISWAP_SWAP_ROUTER = 0xE592427A0AEce92De3EbC44e995AE9D83D0A0C62;
    ISwapRouter constant SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);

    modifier onlyHRManager {
        require(msg.sender == hrManagerAddress, NotAuthorized());
        _;
    }

    modifier onlyActiveEmployee {
        require(employeeActive[msg.sender], NotAuthorized());
        _;
    }

    modifier onlyEmployee {
        require(isEmployee[msg.sender], NotAuthorized());
        _;
    }

    constructor(address _hrManagerAddress) {
        hrManagerAddress = _hrManagerAddress;
    }

    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override onlyHRManager {
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
        uint256 amount = convertToCurrentCurrency(employee, computeAccumulatedSalary(employee) + accuredSalaryTillTermination[employee]);
        lastWithdrawn[employee] = block.timestamp;
        accuredSalaryTillTermination[employee] = 0;
        if (isEth[employee]) {
            // TODO ETH transfer
        } else {
            USDC.transfer(employee, amount);
        }
        emit SalaryWithdrawn(employee, isEth[employee], amount);
    }

    function switchCurrency() external override onlyActiveEmployee {
        address employee = msg.sender;
        withdrawSalary();
        isEth[employee] = !isEth[employee];
        emit CurrencySwitched(employee, isEth[employee]);
    }

    function salaryAvailable(address employee) external view override returns (uint256) {
        return convertToCurrentCurrency(employee, computeAccumulatedSalary(employee));
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
        uint256 amountInUSD = ((block.timestamp - lastWithdrawn[employee]) * weeklySalary[employee]) / (SECONDS_IN_WEEK);
        return amountInUSD;
    }

    function convertToCurrentCurrency(address employee, uint256 amountInUSD) private view returns (uint256) {
        uint256 USD_TO_USDC = 1e12;
        return (isEth[employee]) ? 0 : amountInUSD / USD_TO_USDC;
    }
}
