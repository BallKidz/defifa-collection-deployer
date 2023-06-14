// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {DefifaScorecardState} from "../enums/DefifaScorecardState.sol";
import {DefifaTierRedemptionWeight} from "../structs/DefifaTierRedemptionWeight.sol";
import {IDefifaDelegate} from "./IDefifaDelegate.sol";

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

    function MAX_ATTESTATION_POWER_TIER() external view returns (uint256);

    function controller() external view returns (IJBController3_1);

    function defaultAttestationDelegateProposalOf(uint256 gameId) external view returns (uint256);

    function ratifiedScorecardIdOf(uint256 gameId) external view returns (uint256);

    function hashScorecardOf(address gameDelegate, bytes memory data) external returns (uint256);

    function stateOf(uint256 gameId, uint256 scorecardId) external view returns (DefifaScorecardState);

    function getAttestationWeight(uint256 gameId, address account, uint256 blockNumber)
        external
        view
        returns (uint256 attestationPower);

    function attestationCountOf(uint256 gameId, uint256 scorecardId) external view returns (uint256);

    function hasAttestedTo(uint256 gameId, uint256 scorecardId, address account) external view returns (bool);

    function attestationStartTimeOf(uint256 gameId) external view returns (uint256);

    function attestationGracePeriodOf(uint256 gameId) external view returns (uint256);

    function quorum(uint256 gameId) external view returns (uint256);

    function initializeGame(uint256 gameId, uint256 attestationStartTime, uint256 attestationGracePeriod) external;

    function submitScorecardFor(uint256 gameId, DefifaTierRedemptionWeight[] calldata tierWeights)
        external
        returns (uint256);

    function attestToScorecardFrom(uint256 gameId, uint256 scorecardId) external returns (uint256 weight);

    function ratifyScorecardFrom(uint256 gameId, DefifaTierRedemptionWeight[] calldata tierWeights)
        external
        returns (uint256);
}
