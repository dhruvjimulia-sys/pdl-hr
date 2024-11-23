// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IHumanResources.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HumanResources is IHumanResources {

    address immutable private hrManagerAddress;
    // OPT: Colalease into one mapping
    mapping(address => bool) private employeeRegistered;
    mapping(address => uint256) private weeklySalary;
    mapping(address => uint256) private employedSince;
    mapping(address => uint256) private terminatedAt;
    mapping(address => uint256) private lastWithdrawn;
    mapping(address => bool) private isEth;
    uint256 private activeEmployeeCount;

    IERC20 constant USDC = IERC20(USDC_ADDRESS);

    modifier onlyHRManager {
        require(msg.sender == hrManagerAddress, NotAuthorized());
        _;
    }

    modifier onlyActiveEmployee {
        require(employeeRegistered[msg.sender], NotAuthorized());
        _;
    }

    constructor(address _hrManagerAddress) {
        hrManagerAddress = _hrManagerAddress;
    }

    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override onlyHRManager {
        require(!employeeRegistered[employee], EmployeeAlreadyRegistered());
        // TODO Reregister unclaimed salary edge case
        employeeRegistered[employee] = true;
        weeklySalary[employee] = weeklyUsdSalary;
        employedSince[employee] = block.timestamp;
        isEth[employee] = false;
        lastWithdrawn[employee] = block.timestamp;
        activeEmployeeCount++;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function terminateEmployee(address employee) external override onlyHRManager {
        require(employeeRegistered[employee], EmployeeNotRegistered());
        employeeRegistered[employee] = false;
        // TODO stop accumulation
        terminatedAt[employee] = block.timestamp;
        activeEmployeeCount--;
        emit EmployeeTerminated(employee);
    }

    function withdrawSalary() external override {
        address memory employee = msg.sender;
        uint256 memory SECONDS_IN_WEEK = 7 * 24 * 3600;
        uint256 memory USD_TO_USDC = 1e12;
        uint256 memory amountInUSD = ((block.timestamp - lastWithdrawn[employee]) * weeklySalary[employee]) / (SECONDS_IN_WEEK);
        uint256 memory amount = 0;
        if (isEth[employee]) {

        } else {
            amount = amountInUSD / USD_TO_USDC;
            // send USDC by using transfer
        }
        lastWithdrawn[msg.sender] = block.timestamp;
        // TODO Accured salary should be zero
        emit SalaryWithdrawn(employee, isEth[employee], amount);
    }

    function switchCurrency() external override onlyActiveEmployee {
        // TODO current pending salary withdrawn
        isEth[msg.sender] = !isEth[msg.sender];
        emit CurrencySwitched(msg.sender, isEth[msg.sender]);
    }

    function salaryAvailable(address employee) external view override returns (uint256) {
        computeAccumulatedSalary();
    }

    function hrManager() external view override returns (address) {
        return hrManagerAddress;
    }

    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }

    function getEmployeeInfo(
        address employee
    ) external view override returns (uint256, uint256, uint256) {
        // TODO employedSince semantics for terminated employees?
        return (weeklySalary[employee], employedSince[employee], terminatedAt[employee]);
    }

    // function computeAccumulatedSalary() {

    // }
}
