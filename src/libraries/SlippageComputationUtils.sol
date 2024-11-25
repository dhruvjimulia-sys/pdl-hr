// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

library SlippageComputationUtils {
    function slippageMinimum(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        return amount * (100 - slippage) / 100;
    }

    function slippageMaximum(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        return amount * (100 + slippage) / 100;
    }
}