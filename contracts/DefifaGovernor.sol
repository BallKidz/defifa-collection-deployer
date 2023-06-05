// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@paulrberg/contracts/math/PRBMath.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "./interfaces/IDefifaGovernor.sol";
import "./interfaces/IDefifaDeployer.sol";
import "./DefifaDelegate.sol";

/**
 * @title
 *   DefifaGovernor
 *
 *   @notice
 *   Governs a Defifa game.
 *
 *   @dev
 *   Adheres to -
 *   IDefifaGovernor: General interface for the generic controller methods in this contract that interacts with funding cycles and tokens according to the protocol's rules.
 *
 *   @dev
 *   Inherits from -
 *   Governor: Standard OZ governor.
 *   GovernorCountingSimple: Simple counting params for Governor.
 */
contract DefifaGovernor is Governor, GovernorCountingSimple, IDefifaGovernor {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error ALREADY_RATIFIED();
    error INCORRECT_TIER_ORDER();
    error UNOWNED_PROPOSED_REDEMPTION_VALUE();
    error DISABLED();

    //*********************************************************************//
    // ---------------- immutable internal stored properties ------------- //
    //*********************************************************************//

    /**
     * @notice
     * The duration of one block.
     */
    uint256 internal immutable _blockTime;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /**
     * @notice
     * The time the vote will be active for once it has started, measured in blocks.
     */
    uint256 internal __votingPeriod;

    //*********************************************************************//
    // ------------------------ public constants ------------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The max voting power each tier has if every token within the tier votes.
     */
    uint256 public constant override MAX_VOTING_POWER_TIER = 1_000_000_000;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /**
     * @notice
     * The address of the origin 'DefifaGovernor', used to check in the init if the contract is the original or not
     */
    address public immutable override codeOrigin;

    //*********************************************************************//
    // -------------------- public stored properties --------------------- //
    //*********************************************************************//

    /**
     * @notice
     * The Defifa delegate contract that this contract is Governing.
     */
    IDefifaDelegate public override delegate;

    /**
     * @notice
     * Voting start timestamp after which voting can begin.
     */
    uint256 public override votingStartTime;

    /**
     * @notice
     * The latest proposal submitted by the default voting delegate.
     */
    uint256 public override defaultVotingDelegateProposal;

    /** 
    * @notice 
    * The proposal that has been ratified.
    */
    uint256 public override ratifiedProposal;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(uint256 __blockTime) Governor("DefifaGovernor") {
        codeOrigin = address(this);
        _blockTime = __blockTime;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /**
     * @notice
     * Initializes the contract.
     *
     * @param _delegate The Defifa delegate contract that this contract is Governing.
     * @param _votingStartTime Voting start time.
     * @param _votingPeriod The time the vote will be active for once it has started. This is one weeks by default.
     */
    function initialize(IDefifaDelegate _delegate, uint256 _votingStartTime, uint256 _votingPeriod)
        public
        virtual
        override
    {
        // Make the original un-initializable.
        if (address(this) == codeOrigin) revert();

        // Stop re-initialization.
        if (address(delegate) != address(0)) revert();

        delegate = _delegate;
        votingStartTime = _votingStartTime;
        __votingPeriod = _votingPeriod;
    }

    /**
     * @notice
     * Submits a scorecard to be voted on.
     *
     * @param _tierWeights The weights of each tier in the scorecard.
     *
     * @return proposalId The proposal ID.
     */
    function submitScorecard(DefifaTierRedemptionWeight[] calldata _tierWeights)
        external
        override
        returns (uint256 proposalId)
    {
        // Make sure no weight is assigned to an unowned tier.
        uint256 _numberOfTierWeights = _tierWeights.length;

        for (uint256 _i; _i < _numberOfTierWeights;) {
            // Get a reference to the tier.
            JB721Tier memory _tier = delegate.store().tierOf(address(delegate), _tierWeights[_i].id, false);

            // If there's a weight assigned to the tier, make sure there is a token backed by it.
            if (_tier.initialQuantity == _tier.remainingQuantity && _tierWeights[_i].redemptionWeight > 0) {
                revert UNOWNED_PROPOSED_REDEMPTION_VALUE();
            }

            unchecked {
                ++_i;
            }
        }

        // Build the calldata normalized such that the Governor contract accepts.
        (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
            _buildScorecardCalldata(_tierWeights);

        // Submit the proposal.
        proposalId = this.propose(_targets, _values, _calldatas, "");

        // Keep a reference to the default voting delegate.
        address _defaultVotingDelegate = delegate.defaultVotingDelegate();

        // If the scorecard is being sent from the default voting delegate, store it.
        if (msg.sender == _defaultVotingDelegate) {
            defaultVotingDelegateProposal = proposalId;
        }

        emit ScorecardSubmitted(proposalId, _tierWeights, msg.sender == _defaultVotingDelegate, msg.sender);
    }

    /**
     * @notice
     * Attests to a scorecard.
     *
     * @param _scorecardId The scorecard ID.
     */
    function attestToScorecard(uint256 _scorecardId) external override {
        // Vote.
        super._castVote(_scorecardId, msg.sender, 1, "", _defaultParams());
    }

    /**
     * @notice
     * Attests to a scorecard with the set of ordered tier id's.
     *
     * @param _scorecardId The scorecard ID.
     */
    function attestToScorecardWithReasonAndParams(uint256 _scorecardId, bytes memory params) external override {
        // Vote.
        super._castVote(_scorecardId, msg.sender, 1, "", params);
    }

    /**
     * @notice
     * Ratifies a scorecard that has been approved.
     *
     * @param _tierWeights The weights of each tier in the approved scorecard.
     *
     * @return proposalId The proposal ID.
     */
    function ratifyScorecard(DefifaTierRedemptionWeight[] calldata _tierWeights) external override returns (uint256 proposalId) {
        // Build the calldata to the delegate
        (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
            _buildScorecardCalldata(_tierWeights);

        if (ratifiedProposal != 0) revert ALREADY_RATIFIED();

        // Attempt to execute the proposal.
        proposalId = this.execute(_targets, _values, _calldatas, keccak256(""));

        // Set the ratifies proposal.
        ratifiedProposal = proposalId;
    }

    function execute(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public payable virtual override returns (uint256) {
      // We don't allow executing proposals other than scorecards
      if (_msgSender() != address(this)) revert DISABLED();

      super.execute(_targets, _values, _calldatas, _descriptionHash);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /**
     * @notice
     * Build the calldata normalized such that the Governor contract accepts.
     *
     * @param _tierWeights The weights of each tier in the scorecard data.
     *
     * @return The targets to send transactions to.
     * @return The values to send allongside the transactions.
     * @return The calldata to send allongside the transactions.
     */
    function _buildScorecardCalldata(DefifaTierRedemptionWeight[] calldata _tierWeights)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        // Set the one target to be the delegate's address.
        address[] memory _targets = new address[](1);
        _targets[0] = address(delegate);

        // There are no values sent.
        uint256[] memory _values = new uint256[](1);

        // Build the calldata from the tier weights.
        bytes memory _calldata =
            abi.encodeWithSelector(DefifaDelegate.setTierRedemptionWeights.selector, (_tierWeights));

        // Add the calldata.
        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = _calldata;

        return (_targets, _values, _calldatas);
    }

    /**
     * @notice
     * Gets an account's voting power given a number of tiers to look through.
     *
     * @param _account The account to get votes for.
     * @param _blockNumber The block number to measure votes from.
     * @param _params The params to decode tier ID's from.
     *
     * @return votingPower The amount of voting power.
     */
    function _getVotes(address _account, uint256 _blockNumber, bytes memory _params)
        internal
        view
        virtual
        override(Governor)
        returns (uint256 votingPower)
    {
        // Decode the tier IDs from the provided param bytes.
        uint256[] memory _tierIds = abi.decode(_params, (uint256[]));

        // Keep a reference to the number of tiers.
        uint256 _numbeOfTiers = _tierIds.length;

        // Loop over all tiers gathering the voting share of the provided account.
        uint256 _prevTierId;

        // Keep a reference to the tier being iterated on.
        uint256 _tierId;

        for (uint256 _i; _i < _numbeOfTiers;) {
            // Set the tier being iterated on.
            _tierId = _tierIds[_i];

            // Enforce the tiers to be in ascending order to make sure there aren't duplicate tier IDs in the params.
            if (_tierId <= _prevTierId) revert INCORRECT_TIER_ORDER();

            // Set the previous tier ID.
            _prevTierId = _tierId;

            // Keep a reference to the number of tier votes for the account.
            uint256 _tierVotesForAccount = delegate.getPastTierVotes(_account, _tierId, _blockNumber);

            // If there is tier voting power, increment the result by the proportion of votes the account has to the total, multiplied by the tier's maximum vote power.
            unchecked {
                if (_tierVotesForAccount != 0) {
                    votingPower += PRBMath.mulDiv(
                        MAX_VOTING_POWER_TIER,
                        _tierVotesForAccount,
                        delegate.getPastTierTotalVotes(_tierId, _blockNumber)
                    );
                }
            }

            ++_i;
        }
    }

    /**
     * @notice
     * By default, look for voting power within all tiers.
     *
     * @return votingPower The amount of voting power.
     */
    function _defaultParams() internal view virtual override returns (bytes memory) {
        // Get a reference to the number of tiers.
        uint256 _count = delegate.store().maxTierIdOf(address(delegate));

        // Initialize an array to store the IDs.
        uint256[] memory _ids = new uint256[](_count);

        // Add all tiers to the array.
        for (uint256 _i; _i < _count;) {
            // Tiers start counting from 1.
            _ids[_i] = _i + 1;

            unchecked {
                ++_i;
            }
        }

        // Return the encoded IDs.
        return abi.encode(_ids);
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 _proposalId) public view virtual override returns (ProposalState) {
        if (ratifiedProposal != 0) {
          return ratifiedProposal == _proposalId ? ProposalState.Succeeded : ProposalState.Defeated;
        }

        uint256 _snapshot = proposalSnapshot(_proposalId);

        if (_snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        if (_snapshot >= block.number) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(_proposalId);

        if (deadline >= block.number) {
            return ProposalState.Active;
        }

        if (_quorumReached(_proposalId) && _voteSucceeded(_proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Active;
        }
    }

    /**
     * @notice
     * Calculating the voting delay based on the votingStartTime configured in the constructor.
     *
     * @dev
     * Delay, in number of block, between when the proposal is created and the vote starts. This can be increassed to
     * leave time for users to buy voting power, or delegate it, before the voting of a proposal starts.
     *
     * @return The delay in number of blocks.
     */
    function votingDelay() public view override(IGovernor) returns (uint256) {
        return votingStartTime > block.timestamp ? (votingStartTime - block.timestamp) / _blockTime : 0;
    }

    /**
     * @notice
     * The amount of time that must go by for voting on a proposal to no longer be allowed.
     */
    function votingPeriod() public view override(IGovernor) returns (uint256) {
        return __votingPeriod / _blockTime;
    }

    /**
     * @notice
     * The number of voting units that must have participated in a vote for it to be ratified.
     */
    function quorum(uint256) public view override(IGovernor) returns (uint256) {
        return (delegate.store().maxTierIdOf(address(delegate)) / 2) * MAX_VOTING_POWER_TIER;
    }

    // Required override.
    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public override(Governor) returns (uint256) {
        // We don't allow submitting proposals other than scorecards
        if (_msgSender() != address(this)) revert DISABLED();

        return super.propose(_targets, _values, _calldatas, _description);
    }

    // Required override.
    function proposalThreshold() public pure override(Governor) returns (uint256) {
        return 0; //
    }

    // Required override.
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    // Required override.
    function _cancel(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) internal override(Governor) returns (uint256) {
      revert DISABLED();
    }

    // Required override.
    function _executor() internal view override(Governor) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
