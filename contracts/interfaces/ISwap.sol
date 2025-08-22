// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interface for the Swap contract
interface ISwap {
    function swap(
        address token0,
        address token1,
        uint256 amount0
    ) external payable returns (uint256);
    
    function estimate(
        address token0,
        address token1,
        uint256 amount0
    ) external view returns (uint256);
}