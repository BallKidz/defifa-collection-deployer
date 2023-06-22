// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import {IJBTiered721DelegateStore} from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import {IJB721TokenUriResolver} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721TokenUriResolver.sol";
import {DefifaTierParams} from "./DefifaTierParams.sol";
import {DefifaOpsData} from "./DefifaOpsData.sol";

/// @custom:member name The name of the game being created.
/// @custom:member projectMetadata Metadata to associate with the project within a particular domain.
/// @custom:member contractUri The URI to associate with the 721.
/// @custom:member baseUri The URI base to prepend onto any tier token URIs.
/// @custom:member tiers Parameters describing the tiers.
/// @custom:member token The token the game is played with.
/// @custom:member mintPeriodDuration The duration of the game's mint phase, measured in seconds.
/// @custom:member refundPeriodDuration The time between the mint phase and the start time when mint's are no longer open but refunds are still allowed, measured in seconds.
/// @custom:member start The time at which the game should start, measured in seconds.
/// @custom:member splits Splits to distribute funds between during the game's scoring phase.
/// @custom:member attestationStartTime The time the attestations will start for all submitted scorecards, measured in seconds. If in the past, scorecards will start accepting attestations right away.
/// @custom:member attestationGracePeriod The time period the attestations must be active for once it has started even if it has already reached quorum, measured in seconds.
/// @custom:member defaultAttestationDelegate The address that'll be set as the attestation delegate by default.
/// @custom:member defaultTokenUriResolver The contract used to resolve token URIs if not provided by a tier specifically.
/// @custom:member terminal The payment terminal where the project will accept funds through.
/// @custom:member store A contract to store standard JB721 data in.
struct DefifaLaunchProjectData {
    string name;
    JBProjectMetadata projectMetadata;
    string contractUri;
    string baseUri;
    DefifaTierParams[] tiers;
    address token;
    uint24 mintPeriodDuration;
    uint24 refundPeriodDuration;
    uint48 start;
    JBSplit[] splits;
    uint256 attestationStartTime;
    uint256 attestationGracePeriod;
    address defaultAttestationDelegate;
    IJB721TokenUriResolver defaultTokenUriResolver;
    IJBPaymentTerminal terminal;
    IJBTiered721DelegateStore store;
}
