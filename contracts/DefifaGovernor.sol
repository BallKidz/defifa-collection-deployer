// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@paulrberg/contracts/math/PRBMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IDefifaGovernor.sol";
import "./structs/DefifaScorecard.sol";
import "./structs/DefifaAttestations.sol";
import "./DefifaDelegate.sol";

/// @title DefifaGovernor
/// @notice Manages the ratification of Defifa scorecards.
contract DefifaGovernor is Ownable, IDefifaGovernor {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error ALREADY_ATTESTED();
    error ALREADY_RATIFIED();
    error GAME_NOT_FOUND();
    error NOT_ALLOWED();
    error DUPLICATE_SCORECARD();
    error INCORRECT_TIER_ORDER();
    error UNKNOWN_PROPOSAL();
    error UNOWNED_PROPOSED_REDEMPTION_VALUE();

    //*********************************************************************//
    // ---------------- immutable internal stored properties ------------- //
    //*********************************************************************//

    /// @notice The duration of one block.
    uint256 internal immutable _blockTime;

    /// @notice The scorecards.
    /// _gameId The ID of the game for which the scorecard affects.
    /// _scorecardId The ID of the scorecard to retrieve.
    mapping(uint256 => mapping(uint256 => DefifaScorecard)) internal _scorecardOf;

    /// @notice The attestations to a scorecard
    /// _gameId The ID of the game for which the scorecard affects.
    /// _scorecardId The ID of the scorecard that has been attested to.
    mapping(uint256 => mapping(uint256 => DefifaAttestations)) internal _scorecardAttestationsOf;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice The time the vote will be active for once it has started, measured in seconds.
    /// _gameId The ID of the game for which the voting period applies.
    mapping(uint256 => uint256) internal _packedScorecardInfoOf;

    //*********************************************************************//
    // ------------------------ public constants ------------------------- //
    //*********************************************************************//

    /// @notice The max voting power each tier has if every token within the tier votes.
    uint256 public constant override MAX_VOTING_POWER_TIER = 1_000_000_000;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller with which new projects should be deployed.
    IJBController3_1 public immutable override controller;

    //*********************************************************************//
    // -------------------- public stored properties --------------------- //
    //*********************************************************************//

    /// @notice The latest proposal submitted by the default voting delegate.
    /// _gameId The ID of the game of the default voting delegate proposal.
    mapping(uint256 => uint256) public override defaultAttestationDelegateProposalOf;

    /// @notice The scorecard that has been ratified.
    /// _gameId The ID of the game of the ratified scorecard.
    mapping(uint256 => uint256) public override ratifiedScorecardIdOf;

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice A value representing the contents of a scorecard.
    /// @param _gameDelegate The address where the game is being played.
    /// @param _calldata The calldata that will be sent if the scorecard is ratified.
    function hashScorecardOf(address _gameDelegate, bytes memory _calldata) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(_gameDelegate, _calldata)));
    }

    /// @notice The state of a proposal.
    /// @param _gameId The ID of the game to get a proposal state of.
    /// @param _scorecardId The ID of the proposal to get the state of.
    /// @return The state.
    function stateOf(uint256 _gameId, uint256 _scorecardId)
        public
        view
        virtual
        override
        returns (DefifaScorecardState)
    {
        // Keep a reference to the ratified scorecard ID.
        uint256 _ratifiedScorecardId = ratifiedScorecardIdOf[_gameId];

        // If the game has already ratified a scorecard, return succeeded if the ratified proposal is being checked. Else return defeated.
        if (_ratifiedScorecardId != 0) {
            return _ratifiedScorecardId == _scorecardId ? DefifaScorecardState.RATIFIED : DefifaScorecardState.DEFEATED;
        }

        // Get a reference to the scorecard.
        DefifaScorecard memory _scorecard = _scorecardOf[_gameId][_scorecardId];

        // Make sure the proposal is known.
        if (_scorecard.attestationsBegin == 0) {
            revert UNKNOWN_PROPOSAL();
        }

        // If the scorecard has attestations beginning in the future, the state is PENDING.
        if (_scorecard.attestationsBegin >= block.number) {
            return DefifaScorecardState.PENDING;
        }

        // If the scorecard has a grace period expiring in the future, the state is ACTIVE.
        if (_scorecard.gracePeriodEnds >= block.number) {
            return DefifaScorecardState.ACTIVE;
        }

        // If quorum has been reached, the state is SUCCEEDED, otherwise it is ACTIVE.
        return quorum(_gameId) <= _scorecardAttestationsOf[_gameId][_scorecardId].count
            ? DefifaScorecardState.SUCCEEDED
            : DefifaScorecardState.ACTIVE;
    }

    /// @notice The amount of time between a scorecard being submitted and attestations to it being enabled, measured in seconds.
    /// @dev This can be increassed to leave time for users to aquire attestation power, or delegate it, before a scorecard becomes live.
    /// @param _gameId The ID of the game to get the attestation delay of.
    /// @return The delay, in seconds.
    function attestationStartTimeOf(uint256 _gameId) public view override returns (uint256) {
        // attestation start time in bits 0-47 (48 bits).
        return uint256(uint48(_packedScorecardInfoOf[_gameId]));
    }

    /// @notice The amount of time that must go by before a scorecard can be ratified.
    /// @param _gameId The ID of the game to get the voting period of.
    /// @return The voting period in number of blocks.
    function attestationGracePeriodOf(uint256 _gameId) public view override returns (uint256) {
        // attestation grace period in bits 48-95 (48 bits).
        return uint256(uint48(_packedScorecardInfoOf[_gameId] >> 48));
    }

    /// @notice The number of voting units that must have participated in a proposal for it to be ratified.
    /// @return The quorum number of votes.
    function quorum(uint256 _gameId) public view override returns (uint256) {
        // Get the game's current funding cycle along with its metadata.
        (, JBFundingCycleMetadata memory _metadata) = controller.currentFundingCycleOf(_gameId);

        return (IDefifaDelegate(_metadata.dataSource).store().maxTierIdOf(_metadata.dataSource) / 2)
            * MAX_VOTING_POWER_TIER;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(IJBController3_1 _controller, uint256 __blockTime) {
        controller = _controller;
        _blockTime = __blockTime;
    }

    //*********************************************************************//
    // ----------------------- public transactions ----------------------- //
    //*********************************************************************//

    /// @notice Initializes a game.
    /// @param _attestationStartTime The amount of time between a scorecard being submitted and attestations to it being enabled, measured in seconds.
    /// @param _attestationGracePeriod The amount of time that must go by before a scorecard can be ratified.
    function initializeGame(uint256 _gameId, uint256 _attestationStartTime, uint256 _attestationGracePeriod)
        public
        virtual
        override
        onlyOwner
    {

        // Set a default attestation start time if needed.
        if (_attestationStartTime == 0) _attestationStartTime = block.timestamp;

        // Pack the values.
        uint256 _packed;
        // attestation start time in bits 0-47 (48 bits).
        _packed |= _attestationStartTime;
        // attestation grace period in bits 48-95 (48 bits).
        _packed |= _attestationGracePeriod << 48;

        // Store the packed value.
        _packedScorecardInfoOf[_gameId] = _packed;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Submits a scorecard to be attested to.
    /// @param _tierWeights The weights of each tier in the scorecard.
    /// @return scorecardId The scorecard's ID.
    function submitScorecardFor(uint256 _gameId, DefifaTierRedemptionWeight[] calldata _tierWeights)
        external
        override
        returns (uint256 scorecardId)
    {
        // Make sure a proposal hasn't yet been ratified.
        if (ratifiedScorecardIdOf[_gameId] != 0) revert ALREADY_RATIFIED();

        // Make sure the game has been initialized.
        if (_packedScorecardInfoOf[_gameId] == 0) revert GAME_NOT_FOUND();

        // Make sure no weight is assigned to an unowned tier.
        uint256 _numberOfTierWeights = _tierWeights.length;

        // Get the game's current funding cycle along with its metadata.
        (, JBFundingCycleMetadata memory _metadata) = controller.currentFundingCycleOf(_gameId);

        for (uint256 _i; _i < _numberOfTierWeights;) {
            // Get a reference to the tier.
            JB721Tier memory _tier =
                IDefifaDelegate(_metadata.dataSource).store().tierOf(_metadata.dataSource, _tierWeights[_i].id, false);

            // If there's a weight assigned to the tier, make sure there is a token backed by it.
            if (_tier.initialQuantity == _tier.remainingQuantity && _tierWeights[_i].redemptionWeight > 0) {
                revert UNOWNED_PROPOSED_REDEMPTION_VALUE();
            }

            unchecked {
                ++_i;
            }
        }

        // Hash the scorecard.
        scorecardId = hashScorecardOf(_metadata.dataSource, _buildScorecardCalldataFor(_tierWeights));

        // Store the scorecard
        DefifaScorecard storage _scorecard = _scorecardOf[_gameId][scorecardId];
        if (_scorecard.attestationsBegin != 0) revert DUPLICATE_SCORECARD();

        uint256 _attestationStartTime = attestationStartTimeOf(_gameId);
        uint256 _timeUntilAttestationsBegin =
            block.timestamp > _attestationStartTime ? block.timestamp : _attestationStartTime - block.timestamp;
        _scorecard.attestationsBegin = uint48(block.number + (_timeUntilAttestationsBegin / _blockTime));
        _scorecard.gracePeriodEnds = uint48(attestationGracePeriodOf(_gameId) / _blockTime);

        // Keep a reference to the default attestation delegate.
        address _defaultAttestationDelegate = IDefifaDelegate(_metadata.dataSource).defaultVotingDelegate();

        // If the scorecard is being sent from the default attestation delegate, store it.
        if (msg.sender == _defaultAttestationDelegate) {
            defaultAttestationDelegateProposalOf[_gameId] = scorecardId;
        }

        emit ScorecardSubmitted(_gameId, scorecardId, _tierWeights, msg.sender == _defaultAttestationDelegate, msg.sender);
    }

    /// @notice Attests to a scorecard.
    /// @param _gameId The ID of the game to which the scorecard belongs.
    /// @param _scorecardId The scorecard ID.
    /// @return weight The attestation weight that was applied.
    function attestToScorecardFrom(uint256 _gameId, uint256 _scorecardId) external override returns (uint256 weight) {
        // Keep a reference to the scorecard being attested to.
        DefifaScorecard storage _scorecard = _scorecardOf[_gameId][_scorecardId];

        // Keep a reference to the scorecard state.
        DefifaScorecardState _state = stateOf(_gameId, _scorecardId);

        if (_state != DefifaScorecardState.ACTIVE && _state != DefifaScorecardState.SUCCEEDED) {
            revert NOT_ALLOWED();
        }

        // Get a reference to the attestation weight.
        weight = _getAttestationWeight(_gameId, msg.sender, _scorecard.attestationsBegin);

        // Keep a reference to the attestations for the scorecard.
        DefifaAttestations storage _attestations = _scorecardAttestationsOf[_gameId][_scorecardId];

        // Make sure the account isn't attesting to the same scorecard again.
        if (_attestations.hasAttested[msg.sender]) revert ALREADY_ATTESTED();

        // Store the fact that the account has attested to the scorecard.
        _attestations.hasAttested[msg.sender] = true;

        // Increase the attestationc count.
        _attestations.count += weight;

        emit ScorecardAttested(_gameId, _scorecardId, weight, msg.sender);
    }

    /// @notice Ratifies a scorecard that has been approved.
    /// @param _tierWeights The weights of each tier in the approved scorecard.
    /// @return scorecardId The scorecard ID that was ratified.
    function ratifyScorecardFrom(uint256 _gameId, DefifaTierRedemptionWeight[] calldata _tierWeights)
        external
        override
        returns (uint256 scorecardId)
    {
        // Make sure a scorecard hasn't been ratified yet.
        if (ratifiedScorecardIdOf[_gameId] != 0) revert ALREADY_RATIFIED();

        // Get the game's current funding cycle along with its metadata.
        (, JBFundingCycleMetadata memory _metadata) = controller.currentFundingCycleOf(_gameId);

        // Build the calldata to the target
        bytes memory _calldata = _buildScorecardCalldataFor(_tierWeights);

        // Attempt to execute the proposal.
        scorecardId = hashScorecardOf(_metadata.dataSource, _calldata);

        // Make sure the proposal being ratified has suceeded.
        if (stateOf(_gameId, scorecardId) != DefifaScorecardState.SUCCEEDED) revert NOT_ALLOWED();

        // Set the ratified scorecard.
        ratifiedScorecardIdOf[_gameId] = scorecardId;

        // Execute the scorecard.
        (bool success, bytes memory returndata) = _metadata.dataSource.call(_calldata);
        Address.verifyCallResult(success, returndata, "BAD_SCORECARD");

        emit ScorecardRatified(_gameId, scorecardId, msg.sender);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Build the normalized calldata.
    /// @param _tierWeights The weights of each tier in the scorecard data.
    /// @return The calldata to send allongside the transactions.
    function _buildScorecardCalldataFor(DefifaTierRedemptionWeight[] calldata _tierWeights)
        internal
        pure
        returns (bytes memory)
    {
        // Build the calldata from the tier weights.
        return abi.encodeWithSelector(DefifaDelegate.setTierRedemptionWeightsTo.selector, (_tierWeights));
    }

    /// @notice Gets an account's voting power given a number of tiers to look through.
    /// @param _gameId The ID of the game for which votes are being counted.
    /// @param _account The account to get votes for.
    /// @param _blockNumber The block number to measure votes from.
    /// @return votingPower The amount of voting power.
    function _getAttestationWeight(uint256 _gameId, address _account, uint256 _blockNumber)
        internal
        view
        virtual
        returns (uint256 votingPower)
    {
        // Get the game's current funding cycle along with its metadata.
        (, JBFundingCycleMetadata memory _metadata) = controller.currentFundingCycleOf(_gameId);

        // Keep a reference to the number of tiers.
        // Get a reference to the number of tiers.
        uint256 _numbeOfTiers = IDefifaDelegate(_metadata.dataSource).store().maxTierIdOf(_metadata.dataSource);

        // Keep a reference to the tier being iterated on.
        uint256 _tierId;

        for (uint256 _i; _i < _numbeOfTiers;) {
            // Tier's are 1 indexed;
            _tierId = _i + 1;

            // Keep a reference to the number of tier votes for the account.
            uint256 _tierVotesForAccount =
                IDefifaDelegate(_metadata.dataSource).getPastTierAttestationsOf(_account, _tierId, _blockNumber);

            // If there is tier voting power, increment the result by the proportion of votes the account has to the total, multiplied by the tier's maximum vote power.
            unchecked {
                if (_tierVotesForAccount != 0) {
                    votingPower += PRBMath.mulDiv(
                        MAX_VOTING_POWER_TIER,
                        _tierVotesForAccount,
                        IDefifaDelegate(_metadata.dataSource).getPastTierTotalAttestationsOf(_tierId, _blockNumber)
                    );
                }
            }

            ++_i;
        }
    }
}
