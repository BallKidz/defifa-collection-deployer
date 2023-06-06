// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import "./DefifaTierParams.sol";
import "./DefifaTimeData.sol";

 /// @member name The name of the game being created. 
 /// @member projectMetadata Metadata to associate with the project within a particular domain. 
 /// @member contractUri The URI to associate with the 721.
 /// @member baseUri The URI base to prepend onto any tier token URIs.
 /// @member tiers Parameters describing the tiers.
 /// @member token The token the game is played with.
 /// @member mintDuration The duration of the game's mint phase, measured in seconds.
 /// @member refundDuration The time between the mint phase and the start time when mint's are no longer open but refunds are still allowed, measured in seconds.
 /// @member start The time at which the game should start, measured in seconds.
 /// @member splits Splits to distribute funds between during the game's scoring phase.
 /// @member distributionLimit The amount of funds to distribute from the pot during the game's scoring phase.
 /// @member ballkidzFeeProjectTokenAccount The address that should be sent $DEFIFA tokens that are minted from paying the fee.
 /// @member votingStartTime The time the vote will start for all submitted proposals. If in the past, proposals will start accepting votes right away.
 /// @member votingPeriod The time period the vote must be active for once it has started even if it has already reached quorum, measured in seconds.
 /// @member defaultVotingDelegate The address that'll be set as the voting delegate by default.
 /// @member defaultTokenUriResolver The contract used to resolve token URIs if not provided by a tier specifically.
 /// @member terminal The payment terminal where the project will accept funds through.
 /// @member store A contract to store standard JB721 data in.
struct DefifaLaunchProjectData {
    string name;
    JBProjectMetadata projectMetadata;
    string contractUri;
    string baseUri;
    DefifaTierParams[] tiers;
    address token;
    uint48 mintDuration;
    uint48 refundDuration;
    uint48 start;
    JBSplit[] splits;
    uint88 distributionLimit;
    address payable ballkidzFeeProjectTokenAccount;
    uint256 votingStartTime;
    uint256 votingPeriod;
    address defaultVotingDelegate;
    IJBTokenUriResolver defaultTokenUriResolver;
    IJBPaymentTerminal terminal;
    IJBTiered721DelegateStore store;
}
