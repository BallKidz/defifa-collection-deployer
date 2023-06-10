// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "../enums/DefifaScorecardState.sol";
import "../structs/DefifaTierRedemptionWeight.sol";
import "./IDefifaDelegate.sol";

interface IDefifaGovernor {
    event ScorecardSubmitted(
        uint256 indexed gameId,
        uint256 indexed scorecardId,
        DefifaTierRedemptionWeight[] tierWeights,
        bool isDefaultAttestationDelegate,
        address caller
    );

    event ScorecardAttested(uint256 indexed gameId, uint256 indexed scorecardId, uint256 weight, address caller);

    event ScorecardRatified(uint256 indexed gameId, uint256 indexed scorecardId, address caller);

    function MAX_VOTING_POWER_TIER() external view returns (uint256);

    function controller() external view returns (IJBController3_1);

    function defaultAttestationDelegateProposalOf(uint256 _gameId) external view returns (uint256);

    function ratifiedScorecardIdOf(uint256 _gameId) external view returns (uint256);

    function hashScorecardOf(address _gameDelegate, bytes memory _calldata) external returns (uint256);

    function stateOf(uint256 _gameId, uint256 _scorecardId) external view returns (DefifaScorecardState);

    function getAttestationWeight(uint256 _gameId, address _account, uint256 _blockNumber)
        external
        view
        returns (uint256 votingPower);

    function attestationStartTimeOf(uint256 _gameId) external view returns (uint256);

    function attestationGracePeriodOf(uint256 _gameId) external view returns (uint256);

    function quorum(uint256 _gameId) external view returns (uint256);

    function initializeGame(uint256 _gameId, uint256 _attestationStartTime, uint256 _attestationGracePeriod) external;

    function submitScorecardFor(uint256 _gameId, DefifaTierRedemptionWeight[] calldata _tierWeights)
        external
        returns (uint256);

    function attestToScorecardFrom(uint256 _gameId, uint256 _scorecardId) external returns (uint256 weight);

    function ratifyScorecardFrom(uint256 _gameId, DefifaTierRedemptionWeight[] calldata _tierWeights)
        external
        returns (uint256);
}
