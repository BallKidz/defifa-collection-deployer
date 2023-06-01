// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IDefifaGamePotReporter {
    function gamePotOf(uint256 _gameId) external view returns (uint256, address, uint256);
}