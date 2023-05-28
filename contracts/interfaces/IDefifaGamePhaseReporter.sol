// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './../enums/DefifaGamePhase.sol';

interface IDefifaGamePhaseReporter {
  function currentGamePhaseOf(uint256 _gameId) external view returns (DefifaGamePhase);
}
