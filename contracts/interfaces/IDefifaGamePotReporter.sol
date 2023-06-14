// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IDefifaGamePotReporter {
    function currentGamePotOf(uint256 gameId) external view returns (uint256, address, uint256);
}
