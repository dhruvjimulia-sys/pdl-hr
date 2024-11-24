// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../interfaces/chainlink/AggregatorV3Interface.sol";

library CurrencyConvertUtils {
    function convertUSDToETH(uint256 amountInUSD, AggregatorV3Interface ethUsdFeed) external view returns (uint256) {
        (, int256 ethPrice,,,) = ethUsdFeed.latestRoundData();
        require(ethPrice > 0, "ETH price from oracle less than or equal to 0");
        uint256 ETH_TO_USD = 1e10;
        return (amountInUSD * 1e18) / (uint256(ethPrice) * ETH_TO_USD);
    }
}