// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IDefifaNoContestReporter {
  function isNoContest(uint256 _gameId) external view  returns (bool);
}
