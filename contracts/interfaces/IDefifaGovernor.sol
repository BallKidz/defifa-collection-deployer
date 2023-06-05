// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../structs/DefifaTierRedemptionWeight.sol";
import "./IDefifaDelegate.sol";

interface IDefifaGovernor {
    event ScorecardSubmitted(
        uint256 proposalId, DefifaTierRedemptionWeight[] tierWeights, bool isDefaultVotingDelegate, address caller
    );

    function MAX_VOTING_POWER_TIER() external view returns (uint256);

    function codeOrigin() external view returns (address);

    function delegate() external view returns (IDefifaDelegate);

    function votingStartTime() external view returns (uint256);

    function defaultVotingDelegateProposal() external view returns (uint256);

    function ratifiedProposal() external view returns (uint256);

    function initialize(IDefifaDelegate _delegate, uint256 _votingStartTime, uint256 _votingPeriod) external;

    function submitScorecard(DefifaTierRedemptionWeight[] calldata _tierWeights) external returns (uint256);

    function attestToScorecard(uint256 _scorecardId) external;

    function attestToScorecardWithReasonAndParams(uint256 _scorecardId, bytes memory params) external;

    function ratifyScorecard(DefifaTierRedemptionWeight[] calldata _tierWeights) external returns (uint256);
}
