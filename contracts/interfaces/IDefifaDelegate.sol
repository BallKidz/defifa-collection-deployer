// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721TieredGovernance.sol';

import './../structs/DefifaTierRedemptionWeight.sol';

interface IDefifaDelegate is IJB721TieredGovernance {
  function TOTAL_REDEMPTION_WEIGHT() external view returns (uint256);

  function name() external view returns (string memory);

  function redemptionWeightOf(uint256 _tokenId) external view returns (uint256);

  function tierRedemptionWeights() external view returns (uint256[128] memory);

  function setTierRedemptionWeights(DefifaTierRedemptionWeight[] memory _tierWeights) external;
}
