// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IHumanResources.sol";

contract HumanResources is IHumanResources {
    address immutable private hrManagerAddress;
    // OPT: Colalease into one mapping
    mapping(address => bool) private employeeRegistered;
    mapping(address => uint256) private weeklySalary;
    mapping(address => uint256) private timestampRegistered;

    constructor(address _hrManagerAddress) {
        hrManagerAddress = _hrManagerAddress;
    }

    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override {
        require(employeeRegistered[employee], EmployeeAlreadyRegistered());
        employeeRegistered[employee] = true;
        weeklySalary[employee] = weeklyUsdSalary;
        timestampRegistered[employee] = block.timestamp;
    }

    function terminateEmployee(address employee) external {

    }

    function withdrawSalary() external {

    }

    function switchCurrency() external {

    }

    function salaryAvailable(address employee) external view returns (uint256) {

    }

    function hrManager() external view returns (address) {
        return address(0);
    }

    function getActiveEmployeeCount() external view returns (uint256) {
        return 0;
    }

    function getEmployeeInfo(
        address employee
    )
        external
        view
        returns (
            uint256 weeklyUsdSalary,
            uint256 employedSince,
            uint256 terminatedAt
        ) {

        }
}
