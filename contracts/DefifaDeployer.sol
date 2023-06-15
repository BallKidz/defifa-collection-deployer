// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {JBConstants} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import {JBTokens} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import {JBSplitsGroups} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";
import {IJBAllowanceTerminal3_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBAllowanceTerminal3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBPayoutRedemptionPaymentTerminal3_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {JBTiered721FundingCycleMetadataResolver} from
    "@jbx-protocol/juice-721-delegate/contracts/libraries/JBTiered721FundingCycleMetadataResolver.sol";
import {IJB721TokenUriResolver} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierParams} from "@jbx-protocol/juice-721-delegate/contracts/structs/JB721TierParams.sol";
import {JBTiered721FundingCycleMetadata} from
    "@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721FundingCycleMetadata.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {DefifaGamePhase} from "./enums/DefifaGamePhase.sol";
import {IDefifaDeployer} from "./interfaces/IDefifaDeployer.sol";
import {IDefifaDelegate} from "./interfaces/IDefifaDelegate.sol";
import {IDefifaGamePhaseReporter} from "./interfaces/IDefifaGamePhaseReporter.sol";
import {IDefifaGamePotReporter} from "./interfaces/IDefifaGamePotReporter.sol";
import {IDefifaGovernor} from "./interfaces/IDefifaGovernor.sol";
import {DefifaLaunchProjectData} from "./structs/DefifaLaunchProjectData.sol";
import {DefifaTierParams} from "./structs/DefifaTierParams.sol";
import {DefifaOpsData} from "./structs/DefifaOpsData.sol";
import {DefifaDelegate} from "./DefifaDelegate.sol";
import {DefifaTokenUriResolver} from "./DefifaTokenUriResolver.sol";

/// @title DefifaDeployer
/// @notice Deploys and manages Defifa games.
contract DefifaDeployer is
    Ownable,
    IDefifaDeployer,
    IDefifaGamePhaseReporter,
    IDefifaGamePotReporter,
    IERC721Receiver
{
    using Strings for uint256;
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error CANT_FULFILL_YET();
    error GAME_OVER();
    error INVALID_FEE_PERCENT();
    error INVALID_GAME_CONFIGURATION();
    error INCORRECT_DECIMAL_AMOUNT();
    error TERMINAL_NOT_FOUND();
    error PHASE_ALREADY_QUEUED();
    error SPLITS_DONT_ADD_UP();
    error UNEXPECTED_TERMINAL_CURRENCY();

    //*********************************************************************//
    // ----------------------- internal constants ------------------------ //
    //*********************************************************************//

    /// @notice The ID of the project that takes fees upon distribution.
    uint256 internal constant _PROTOCOL_FEE_PROJECT = 1;

    /// @notice Useful for the deploy flow to get memory management right.
    uint256 internal constant _DEPLOY_BYTECODE_LENGTH = 13;

    //*********************************************************************//
    // ----------------------- internal properties ----------------------- //
    //*********************************************************************//

    /// @notice The game's ops.
    mapping(uint256 => DefifaOpsData) internal _opsOf;

    /// @notice This contract current nonce, used for the registry initialized at 1 since the first contract deployed is the delegate
    uint256 internal _nonce;

    /// @notice If each game has been set to no contest.
    mapping(uint256 => bool) internal _noContestIsSet;

    //*********************************************************************//
    // ------------------ public immutable properties -------------------- //
    //*********************************************************************//

    /// @notice The group relative to which splits are stored.
    /// @dev This could be any fixed number.
    uint256 public immutable override splitGroup;

    /// @notice The project ID relative to which splits are stored.
    /// @dev The owner of this project ID must give this contract operator permissions over the SET_SPLITS operation.
    uint256 public immutable override ballkidzProjectId;

    /// @notice The original code for the Defifa delegate to base subsequent instances on.
    address public immutable override delegateCodeOrigin;

    /// @notice The default Defifa token URI resolver.
    IJB721TokenUriResolver public immutable override tokenUriResolver;

    /// @notice The Defifa governor.
    IDefifaGovernor public immutable override governor;

    /// @notice The controller with which new projects should be deployed.
    IJBController3_1 public immutable override controller;

    /// @notice The address that should be forwarded JBX accumulated in this contract from game fund distributions.
    address public immutable override protocolFeeProjectTokenAccount;

    /// @notice The delegates registry.
    IJBDelegatesRegistry public immutable delegatesRegistry;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The divisor that describes the fee that should be taken.
    /// @dev This is equal to 100 divided by the fee percent.
    uint256 public override feeDivisor = 20;

    /// @notice A flag indicating if a game's commitments have been fulfilled.
    /// @dev The ID of the game to check.
    mapping(uint256 => bool) public override hasFulfilledCommitments;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The game times.
    /// @param _gameId The ID of the game for which the game times apply.
    /// @return The game's start time, as a unix timestamp.
    /// @return The game's minting period duration, in seconds.
    /// @return The game's refund period duration, in seconds.
    function timesFor(uint256 _gameId) external view override returns (uint48, uint24, uint24) {
        DefifaOpsData memory _ops = _opsOf[_gameId];
        return (_ops.start, _ops.mintPeriodDuration, _ops.refundPeriodDuration);
    }

    /// @notice The token of a gmae.
    /// @param _gameId The ID of the game to get the token of.
    /// @return The game's token.
    function tokenOf(uint256 _gameId) external view override returns (address) {
        return _opsOf[_gameId].token;
    }

    /// @notice The current pot the game is being played with.
    /// @param _gameId The ID of the game for which the pot apply.
    /// @return The game's pot amount, as a fixed point number.
    /// @return The token address the game's pot is measured in.
    /// @return The number of decimals included in the amount.
    function currentGamePotOf(uint256 _gameId) external view returns (uint256, address, uint256) {
        // Get a reference to the token being used by the project.
        address _token = _opsOf[_gameId].token;

        // Get a reference to the terminal.
        IJBPaymentTerminal _terminal = controller.directory().primaryTerminalOf(_gameId, _token);

        // Get the current balance.
        uint256 _pot = IJBPayoutRedemptionPaymentTerminal3_1(address(_terminal)).store().currentOverflowOf(
            IJBSingleTokenPaymentTerminal(address(_terminal)), _gameId
        );

        return (_pot, _token, IJBSingleTokenPaymentTerminal(address(_terminal)).decimals());
    }

    /// @notice Whether or not the next phase still needs queuing.
    /// @param _gameId The ID of the game to get the queue status of.
    /// @return Whether or not the next phase still needs queuing.
    function nextPhaseNeedsQueueing(uint256 _gameId) external view override returns (bool) {
        // Get the project's current funding cycle along with its metadata.
        JBFundingCycle memory _currentFundingCycle = controller.fundingCycleStore().currentOf(_gameId);
        // Get the project's queued funding cycle along with its metadata.
        JBFundingCycle memory _queuedFundingCycle = controller.fundingCycleStore().queuedOf(_gameId);

        // If the configurations are the same and the game hasn't ended, queueing is still needed.
        return _currentFundingCycle.duration != 0
            && _currentFundingCycle.configuration == _queuedFundingCycle.configuration;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the number of the game phase.
    /// @dev The game phase corresponds to the game's current funding cycle number.
    /// @param _gameId The ID of the game to get the phase number of.
    /// @return The game phase.
    function currentGamePhaseOf(uint256 _gameId) public view override returns (DefifaGamePhase) {
        // Get the project's current funding cycle along with its metadata.
        (JBFundingCycle memory _currentFundingCycle, JBFundingCycleMetadata memory _metadata) =
            controller.currentFundingCycleOf(_gameId);

        if (_currentFundingCycle.number == 0) return DefifaGamePhase.COUNTDOWN;
        if (_currentFundingCycle.number == 1) return DefifaGamePhase.MINT;
        if (_noContestIsSet[_gameId]) return DefifaGamePhase.NO_CONTEST;
        if (_noContestInevitable(_gameId, _currentFundingCycle)) return DefifaGamePhase.NO_CONTEST_INEVITABLE;
        if (_currentFundingCycle.number == 2 && _opsOf[_gameId].refundPeriodDuration != 0) {
            return DefifaGamePhase.REFUND;
        }
        if (IDefifaDelegate(_metadata.dataSource).redemptionWeightIsSet()) return DefifaGamePhase.COMPLETE;
        return DefifaGamePhase.SCORING;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _delegateCodeOrigin The code of the Defifa delegate.
    /// @param _tokenUriResolver The standard default token URI resolver.
    /// @param _governor The Defifa governor.
    /// @param _controller The controller to use to launch the game from.
    /// @param _delegatesRegistry The contract storing references to the deployer of each delegate.
    /// @param _protocolFeeProjectTokenAccount The address that should be forwarded JBX accumulated in this contract from game fund distributions.
    /// @param _ballkidzProjectId The ID of the project that should take the fee from the games.
    /// @param _owner The address that can change the fees.
    constructor(
        address _delegateCodeOrigin,
        IJB721TokenUriResolver _tokenUriResolver,
        IDefifaGovernor _governor,
        IJBController3_1 _controller,
        IJBDelegatesRegistry _delegatesRegistry,
        address _protocolFeeProjectTokenAccount,
        uint256 _ballkidzProjectId,
        address _owner
    ) {
        delegateCodeOrigin = _delegateCodeOrigin;
        tokenUriResolver = _tokenUriResolver;
        governor = _governor;
        controller = _controller;
        protocolFeeProjectTokenAccount = _protocolFeeProjectTokenAccount;
        delegatesRegistry = _delegatesRegistry;
        ballkidzProjectId = _ballkidzProjectId;
        splitGroup = uint256(uint160(address(this)));
        _transferOwnership(_owner);
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// This contract must be payable to receive overflow allowance to settle commitments. 
    receive() external payable { }

    /// @notice Launches a new game owned by this contract with a DefifaDelegate attached.
    /// @param _launchProjectData Data necessary to fulfill the transaction to launch a game.
    /// @return gameId The ID of the newly configured game.
    function launchGameWith(DefifaLaunchProjectData memory _launchProjectData)
        external
        override
        returns (uint256 gameId)
    {
        // Start the game right after the mint and refund durations if it isnt provided.
        if (_launchProjectData.start == 0) {
            _launchProjectData.start = uint48(
                block.timestamp + _launchProjectData.mintPeriodDuration + _launchProjectData.refundPeriodDuration
            );
        }
        // Start minting right away if a start time isn't provided.
        else if (
            _launchProjectData.mintPeriodDuration == 0
                && _launchProjectData.start > block.timestamp + _launchProjectData.refundPeriodDuration
        ) {
            _launchProjectData.mintPeriodDuration =
                uint24(_launchProjectData.start - (block.timestamp + _launchProjectData.refundPeriodDuration));
        }

        // Make sure the provided gameplay timestamps are sequential and that there is a mint duration.
        if (
            _launchProjectData.mintPeriodDuration == 0
                || _launchProjectData.start
                    < block.timestamp + _launchProjectData.refundPeriodDuration + _launchProjectData.mintPeriodDuration
        ) revert INVALID_GAME_CONFIGURATION();

        // Get the game ID, optimistically knowing it will be one greater than the current count.
        gameId = controller.projects().count() + 1;

        {
            // Store the timestamps that'll define the game phases.
            _opsOf[gameId] = DefifaOpsData({
                token: _launchProjectData.token,
                mintPeriodDuration: _launchProjectData.mintPeriodDuration,
                refundPeriodDuration: _launchProjectData.refundPeriodDuration,
                start: _launchProjectData.start
            });

            // Keep a reference to the split percent.
            uint256 _feePercent = JBConstants.SPLITS_TOTAL_PERCENT / feeDivisor;

            // Keep a reference to the number of splits.
            uint256 _numberOfSplits = _launchProjectData.splits.length;

            // Make a new splits where fees will be added to.
            JBSplit[] memory _splits = new JBSplit[](_launchProjectData.splits.length + 1);

            // Copy the splits over.
            for (uint256 _i; _i < _numberOfSplits;) {
              // Copy the split over.
              _splits[_i] = _launchProjectData.splits[_i];  
              unchecked {
                ++_i;
              }
            }

            // Add a split for the Ballkidz fee.
            _splits[_numberOfSplits] = JBSplit({
                preferClaimed: true,
                preferAddToBalance: false,
                percent: _feePercent,
                projectId: ballkidzProjectId,
                beneficiary: _launchProjectData.ballkidzFeeProjectTokenAccount,
                lockedUntil: 0,
                allocator: _launchProjectData.ballkidzFeeProjectTokenAllocator
            });

            // Store the splits.
            JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
            _groupedSplits[0] = JBGroupedSplits({group: splitGroup, splits: _splits});

            // This contract must have SET_SPLITS (index 18) operator permissions.
            controller.splitsStore().set(ballkidzProjectId, gameId, _groupedSplits);
        }

        // Keep track of the number of tiers.
        uint256 _numberOfTiers = _launchProjectData.tiers.length;

        // Create the standard tiers struct that will be populated from the defifa tiers.
        JB721TierParams[] memory _delegateTiers = new JB721TierParams[](
          _launchProjectData.tiers.length
        );

        // Group all the tier names together.
        string[] memory _tierNames = new string[](_launchProjectData.tiers.length);

        // Keep a reference to the tier being iterated on.
        DefifaTierParams memory _defifaTier;

        // Create the delegate tiers from the Defifa tiers.
        for (uint256 _i; _i < _numberOfTiers;) {
            _defifaTier = _launchProjectData.tiers[_i];

            // Set the tier.
            _delegateTiers[_i] = JB721TierParams({
                price: _defifaTier.price,
                initialQuantity: 999_999_999, // The max allowed value.
                votingUnits: 1,
                reservedRate: _defifaTier.reservedRate,
                reservedTokenBeneficiary: _defifaTier.reservedTokenBeneficiary,
                encodedIPFSUri: _defifaTier.encodedIPFSUri,
                category: 0,
                allowManualMint: false,
                shouldUseReservedTokenBeneficiaryAsDefault: _defifaTier.shouldUseReservedTokenBeneficiaryAsDefault,
                transfersPausable: false,
                useVotingUnits: true
            });

            // Set the name.
            _tierNames[_i] = _defifaTier.name;

            unchecked {
                ++_i;
            }
        }

        // Clone and initialize the new delegate with a new token uri resolver.
        DefifaDelegate _delegate = DefifaDelegate(Clones.clone(delegateCodeOrigin));

        // Use the default uri resolver if provided, else use the hardcoded generic default.
        IJB721TokenUriResolver _uriResolver = _launchProjectData.defaultTokenUriResolver
            != IJB721TokenUriResolver(address(0)) ? _launchProjectData.defaultTokenUriResolver : tokenUriResolver;

        _delegate.initialize({
            _gameId: gameId,
            _directory: controller.directory(),
            _name: _launchProjectData.name,
            _symbol: string.concat("DEFIFA ", gameId.toString()),
            _fundingCycleStore: controller.fundingCycleStore(),
            _baseUri: _launchProjectData.baseUri,
            _tokenUriResolver: _uriResolver,
            _contractUri: _launchProjectData.contractUri,
            _tiers: _delegateTiers,
            _currency: uint48(_launchProjectData.terminal.currencyForToken(_launchProjectData.token)),
            _store: _launchProjectData.store,
            _gamePhaseReporter: this,
            _gamePotReporter: this,
            _defaultAttestationDelegate: _launchProjectData.defaultAttestationDelegate,
            _tierNames: _tierNames
        });

        // Queue the mint phase of the game.
        _queueMintPhase(_launchProjectData, address(_delegate));

        // Make sure the provided terminal accepts the same currency as this game is being played in.
        if (!_launchProjectData.terminal.acceptsToken(_launchProjectData.token, gameId)) {
            revert UNEXPECTED_TERMINAL_CURRENCY();
        }

        // Clone and initialize the new governor.
        governor.initializeGame({
            gameId: gameId,
            attestationStartTime: uint256(_launchProjectData.attestationStartTime),
            attestationGracePeriod: uint256(_launchProjectData.attestationGracePeriod)
        });

        // Transfer ownership to the specified owner.
        _delegate.transferOwnership(address(governor));

        // Add the delegate to the registry, contract nonce starts at 1
        delegatesRegistry.addDelegate(address(this), ++_nonce);

        emit LaunchGame(gameId, _delegate, governor, _uriResolver, msg.sender);
    }

    /// @notice Queues the funding cycle that represents the next phase of the game, if it isn't queued already.
    /// @param _gameId The ID of the project having funding cycles reconfigured.
    /// @return configuration The configuration of the funding cycle that was successfully reconfigured.
    function queueNextPhaseOf(uint256 _gameId) external override returns (uint256 configuration) {
        // Get the project's current funding cycle along with its metadata.
        (JBFundingCycle memory _currentFundingCycle, JBFundingCycleMetadata memory _metadata) =
            controller.currentFundingCycleOf(_gameId);

        // No more queuing once duration is set to 0.
        if (_noContestIsSet[_gameId] || _currentFundingCycle.duration == 0) revert GAME_OVER();

        // Check for no contest.
        if (_noContestInevitable(_gameId, _currentFundingCycle)) {
            return _queueNoContest(_gameId, _metadata.dataSource);
        }

        // Get the project's queued funding cycle.
        (JBFundingCycle memory _queuedFundingCycle,) = controller.queuedFundingCycleOf(_gameId);

        // Make sure the next game phase isn't already queued.
        if (_currentFundingCycle.configuration != _queuedFundingCycle.configuration) {
            revert PHASE_ALREADY_QUEUED();
        }

        // Queue the next phase of the game.
        if (_currentFundingCycle.number == 1 && _opsOf[_gameId].refundPeriodDuration != 0) {
            return _queueRefundPhase(_gameId, _metadata.dataSource);
        } else {
            return _queueGamePhase(_gameId, _metadata.dataSource);
        }
    }

    /// @notice Move accumulated protocol project tokens from paying fees into the recipient.
    /// @dev This contract accumulated JBX as games distribute payouts.
    function claimProtocolProjectToken() external override {
        // Get the number of protocol project tokens this contract has allocated.
        // Send the token from the protocol project to the specified account.
        controller.tokenStore().transferFrom(
            address(this),
            _PROTOCOL_FEE_PROJECT,
            protocolFeeProjectTokenAccount,
            controller.tokenStore().unclaimedBalanceOf(address(this), _PROTOCOL_FEE_PROJECT)
        );
    }

    /// @notice Fulfill split amounts between all splits for a game.
    /// @param _gameId The ID of the game to fulfill splits for.
    function fulfillCommitmentsOf(uint256 _gameId) external virtual override {
        // Make sure commitments haven't already been fulfilled.
        if (hasFulfilledCommitments[_gameId]) return;

        // Make sure the game's commitments can be fulfilled.
        {
            DefifaGamePhase _currentGamePhase = currentGamePhaseOf(_gameId);
            if (_currentGamePhase != DefifaGamePhase.SCORING && _currentGamePhase != DefifaGamePhase.COMPLETE) {
                revert CANT_FULFILL_YET();
            }
        }

        // Set the flag to prevent duplicate fulfillments.
        hasFulfilledCommitments[_gameId] = true;

        // Get the splits for the game.
        JBSplit[] memory _splits = controller.splitsStore().splitsOf(ballkidzProjectId, _gameId, splitGroup);

        // Get a reference to the token being used by the game.
        address _token = _opsOf[_gameId].token;

        // Keep a reference to the directory.
        IJBDirectory _directory = controller.directory();

        // Get a reference to the terminal being used.
        IJBPaymentTerminal _terminal = _directory.primaryTerminalOf(_gameId, _token);

        // Get the current pot.
        uint256 _pot = IJBPayoutRedemptionPaymentTerminal3_1(address(_terminal)).store().currentOverflowOf(
            IJBSingleTokenPaymentTerminal(address(_terminal)), _gameId
        );

        // Get the decimals that make up the pot fixed point number.
        uint256 _decimals = IJBSingleTokenPaymentTerminal(address(_terminal)).decimals();

        // Distribute the overflow allowance.
        uint256 _leftoverAmount = IJBAllowanceTerminal3_1(address(_terminal)).useAllowanceOf({
            _projectId: _gameId,
            _amount: _pot,
            _currency: _terminal.currencyForToken(_token),
            _token: _token,
            _minReturnedTokens: _pot,
            _beneficiary: payable(address(this)),
            _memo: string.concat("Settling Defifa game #", _gameId.toString()),
            _metadata: bytes("")
        });

        // Settle between all splits.
        for (uint256 i; i < _splits.length;) {
            // Get a reference to the split being iterated on.
            JBSplit memory _split = _splits[i];

            // The amount to send towards the split.
            uint256 _splitAmount = PRBMath.mulDiv(_pot, _split.percent, JBConstants.SPLITS_TOTAL_PERCENT);

            if (_splitAmount > 0) {
                // Transfer tokens to the split.
                // If there's an allocator set, transfer to its `allocate` function.
                if (_split.allocator != IJBSplitAllocator(address(0))) {
                    // Create the data to send to the allocator.
                    JBSplitAllocationData memory _data = JBSplitAllocationData(
                        _token, _splitAmount, _terminal.decimalsForToken(_token), _gameId, 0, _split
                    );

                    // Approve the `_amount` of tokens for the split allocator to transfer tokens from this contract.
                    if (_token != JBTokens.ETH) {
                        IERC20(_token).safeApprove(address(_split.allocator), _splitAmount);
                    }

                    // If the token is ETH, send it in msg.value.
                    uint256 _payableValue = _token == JBTokens.ETH ? _splitAmount : 0;

                    // Trigger the allocator's `allocate` function.
                    _split.allocator.allocate{value: _payableValue}(_data);

                    // Otherwise, if a project is specified, make a payment to it.
                } else if (_split.projectId != 0) {
                    if (_split.preferAddToBalance) {
                        _addToBalanceOf(
                            _directory,
                            _split.projectId,
                            _token,
                            _splitAmount,
                            _terminal.decimalsForToken(_token),
                            string.concat("Payout from Defifa game #", _gameId.toString()),
                            bytes("")
                        );
                    } else {
                        _pay(
                            _directory,
                            _split.projectId,
                            _token,
                            _splitAmount,
                            _terminal.decimalsForToken(_token),
                            _split.beneficiary != address(0) ? _split.beneficiary : protocolFeeProjectTokenAccount,
                            0,
                            _split.preferClaimed,
                            string.concat("Payout from Defifa game #", _gameId.toString()),
                            bytes("")
                        );
                    }
                } else {
                    // Transfer the ETH.
                    if (_token == JBTokens.ETH) {
                        Address.sendValue(
                            // Get a reference to the address receiving the tokens. If there's a beneficiary, send the funds directly to the beneficiary. Otherwise send to protocolFeeProjectTokenAccount.
                            _split.beneficiary != address(0)
                                ? _split.beneficiary
                                : payable(protocolFeeProjectTokenAccount),
                            _splitAmount
                        );
                    }
                    // Or, transfer the ERC20.
                    else {
                        IERC20(_token).safeTransfer(
                            // Get a reference to the address receiving the tokens. If there's a beneficiary, send the funds directly to the beneficiary. Otherwise send to protocolFeeProjectTokenAccount.
                            _split.beneficiary != address(0) ? _split.beneficiary : protocolFeeProjectTokenAccount,
                            _splitAmount
                        );
                    }
                }

                // Subtract from the amount to be sent to the beneficiary.
                _leftoverAmount = _leftoverAmount - _splitAmount;
            }

            emit DistributeToSplit(_split, _splitAmount, protocolFeeProjectTokenAccount, msg.sender);

            unchecked {
                ++i;
            }
        }

        // Add leftover amount back into the game's pot.
        _addToBalanceOf(_directory, _gameId, _token, _leftoverAmount, _decimals, "Pot", bytes(""));
    }

    /// @notice Allow this contract's owner to change the publishing fee.
    /// @dev The max fee is %5.
    /// @param _percent The percent fee to charge.
    function changeFee(uint256 _percent) external onlyOwner {
        // Make sure the fee is not greater than 5%.
        if (_percent > 10) revert INVALID_FEE_PERCENT();

        // Set the fee divisor.
        feeDivisor = 100 / _percent;
    }

    /// @notice Allows this contract to receive 721s.
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Launches a Defifa project with the minting phase configured.
    /// @param _launchProjectData Project data used for launching a Defifa game.
    /// @param _dataSource The address of the Defifa data source.
    function _queueMintPhase(DefifaLaunchProjectData memory _launchProjectData, address _dataSource) internal {
        // Initialize the terminal array .
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _launchProjectData.terminal;

        // Launch the project with params for phase 1 of the game.
        controller.launchProjectFor(
            // Project is owned by this contract.
            address(this),
            _launchProjectData.projectMetadata,
            JBFundingCycleData({
                duration: _launchProjectData.mintPeriodDuration,
                // Don't mint project tokens.
                weight: 0,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                // Full refunds.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                pausePay: false,
                pauseDistributions: false,
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true,
                useDataSourceForRedeem: true,
                dataSource: _dataSource,
                metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
                    JBTiered721FundingCycleMetadata({
                        pauseTransfers: false,
                        // Reserved tokens can't be minted during this funding cycle.
                        pauseMintingReserves: true
                    })
                    )
            }),
            _launchProjectData.start - _launchProjectData.mintPeriodDuration - _launchProjectData.refundPeriodDuration,
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            _terminals,
            "Defifa mint phase."
        );
    }

    /// @notice Gets reconfiguration data for the refund phase of the game.
    /// @dev This phase freezes mints, but continues to allow refund redemptions.
    /// @param _gameId The ID of the project that's being reconfigured.
    /// @param _dataSource The data source to use.
    /// @return configuration The configuration of the funding cycle that was successfully reconfigured.
    function _queueRefundPhase(uint256 _gameId, address _dataSource) internal returns (uint256 configuration) {
        // Get a reference to the game's ops.
        DefifaOpsData memory _ops = _opsOf[_gameId];

        return controller.reconfigureFundingCyclesOf(
            _gameId,
            JBFundingCycleData({
                duration: _ops.refundPeriodDuration,
                // Don't mint project tokens.
                weight: 0,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                // Full refunds.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                // No more payments.
                pausePay: true,
                pauseDistributions: false,
                // Allow redemptions.
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true,
                useDataSourceForRedeem: true,
                dataSource: _dataSource,
                metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
                    JBTiered721FundingCycleMetadata({
                        pauseTransfers: false,
                        // Reserved tokens can't be minted during this funding cycle.
                        pauseMintingReserves: true
                    })
                    )
            }),
            0, // mustStartAtOrAfter should be ASAP
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            "Defifa refund phase."
        );
    }

    /// @notice Gets reconfiguration data for the game phase.
    /// @dev The game phase freezes the treasury and activates the pre-programmed distribution limit to the specified splits.
    /// @param _gameId The ID of the project that's being reconfigured.
    /// @param _dataSource The data source to use.
    /// @return configuration The configuration of the funding cycle that was successfully reconfigured.
    function _queueGamePhase(uint256 _gameId, address _dataSource) internal returns (uint256 configuration) {
        // Get a reference to the token being used by the project.
        address _token = _opsOf[_gameId].token;

        // Get a reference to the terminal.
        IJBPaymentTerminal _terminal = controller.directory().primaryTerminalOf(_gameId, _token);

        // Set fund access constraints.
        JBFundAccessConstraints[] memory fundAccessConstraints = new JBFundAccessConstraints[](1);
        fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: _terminal,
            token: _token,
            distributionLimit: 0,
            distributionLimitCurrency: 0,
            // Allow a max overflow allowance so that this contract can pull funds to distribute to splits and for fees.
            overflowAllowance: type(uint232).max,
            overflowAllowanceCurrency: _terminal.currencyForToken(_token)
        });

        configuration = controller.reconfigureFundingCyclesOf(
            _gameId,
            JBFundingCycleData({
                duration: 0,
                // Don't mint project tokens.
                weight: 0,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                // Linear redemptions.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                // No more payments.
                pausePay: true,
                pauseDistributions: false,
                // Redemptions allowed.
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true,
                useDataSourceForRedeem: true,
                dataSource: _dataSource,
                metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
                    JBTiered721FundingCycleMetadata({pauseTransfers: false, pauseMintingReserves: false})
                    )
            }),
            0, // mustStartAtOrAfter should be ASAP
            new JBGroupedSplits[](0),
            fundAccessConstraints,
            "Defifa scoring phase."
        );
    }

    /// @notice Gets reconfiguration data for if the game resolves in no contest.
    /// @dev If the game resolves in no contest, funds are made available to minters at the same price that was initially paid.
    /// @param _gameId The ID of the project that's being reconfigured.
    /// @param _dataSource The data source to use.
    /// @return configuration The configuration of the funding cycle that was successfully reconfigured.
    function _queueNoContest(uint256 _gameId, address _dataSource) internal returns (uint256 configuration) {
        configuration = controller.reconfigureFundingCyclesOf(
            _gameId,
            JBFundingCycleData({
                // No duration, lasts indefinately.
                duration: 0,
                // Don't mint project tokens.
                weight: 0,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                // Full refunds.
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                // No more payments.
                pausePay: true,
                pauseDistributions: false,
                // Allow redemptions.
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: true,
                useDataSourceForRedeem: true,
                dataSource: _dataSource,
                metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
                    JBTiered721FundingCycleMetadata({
                        pauseTransfers: false,
                        // Reserved tokens can't be minted during this funding cycle.
                        pauseMintingReserves: true
                    })
                    )
            }),
            0, // mustStartAtOrAfter should be ASAP
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            "Defifa no contest."
        );

        // Set no contest.
        _noContestIsSet[_gameId] = true;
    }

    /// @notice Given a current funding cycle, determine if the game is in no contest.
    /// @param _gameId The ID of the game to check for no contest for.
    /// @param _currentFundingCycle The cycle to check for no contest against.
    /// @return A flag indicating if a game with the current funding cycle is in no contest.
    function _noContestInevitable(uint256 _gameId, JBFundingCycle memory _currentFundingCycle)
        internal
        view
        returns (bool)
    {
        // Get the project's previously configured funding cycle.
        (JBFundingCycle memory _previouslyConfiguredFundingCycle,) =
            controller.getFundingCycleOf(_gameId, _currentFundingCycle.basedOn);

        // If a funding cycle has rolled over, it's in No Contest.
        if (_currentFundingCycle.number != _previouslyConfiguredFundingCycle.number + 1) return true;

        return false;
    }

    /// @notice Make a payment to the specified project.
    /// @param _directory The directory to look for a project's terminal in.
    /// @param _projectId The ID of the project that is being paid.
    /// @param _token The token being paid in.
    /// @param _amount The amount of tokens being paid, as a fixed point number.
    /// @param _decimals The number of decimals in the `_amount` fixed point number.
    /// @param _beneficiary The address who will receive tokens from the payment.
    /// @param _minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with 18 decimals.
    /// @param _preferClaimedTokens A flag indicating whether the request prefers to mint project tokens into the beneficiaries wallet rather than leaving them unclaimed. This is only possible if the project has an attached token contract. Leaving them unclaimed saves gas.
    /// @param _memo A memo to pass along to the emitted event, and passed along the the funding cycle's data source and delegate.  A data source can alter the memo before emitting in the event and forwarding to the delegate.
    /// @param _metadata Bytes to send along to the data source and delegate, if provided.
    function _pay(
        IJBDirectory _directory,
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _decimals,
        address _beneficiary,
        uint256 _minReturnedTokens,
        bool _preferClaimedTokens,
        string memory _memo,
        bytes memory _metadata
    ) internal virtual {
        // Find the terminal for the specified project.
        IJBPaymentTerminal _terminal = _directory.primaryTerminalOf(_projectId, _token);

        // There must be a terminal.
        if (_terminal == IJBPaymentTerminal(address(0))) revert TERMINAL_NOT_FOUND();

        // The amount's decimals must match the terminal's expected decimals.
        if (_terminal.decimalsForToken(_token) != _decimals) revert INCORRECT_DECIMAL_AMOUNT();

        // Approve the `_amount` of tokens from the destination terminal to transfer tokens from this contract.
        if (_token != JBTokens.ETH) IERC20(_token).safeApprove(address(_terminal), _amount);

        // If the token is ETH, send it in msg.value.
        uint256 _payableValue = _token == JBTokens.ETH ? _amount : 0;

        // Send funds to the terminal.
        // If the token is ETH, send it in msg.value.
        _terminal.pay{value: _payableValue}(
            _projectId,
            _amount, // ignored if the token is JBTokens.ETH.
            _token,
            _beneficiary,
            _minReturnedTokens,
            _preferClaimedTokens,
            _memo,
            _metadata
        );
    }

    /// @notice Add to the balance of the specified project.
    /// @param _directory The directory to look for a project's terminal in.
    /// @param _projectId The ID of the project that is being paid.
    /// @param _token The token being paid in.
    /// @param _amount The amount of tokens being paid, as a fixed point number. If the token is ETH, this is ignored and msg.value is used in its place.
    /// @param _decimals The number of decimals in the `_amount` fixed point number. If the token is ETH, this is ignored and 18 is used in its place, which corresponds to the amount of decimals expected in msg.value.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _metadata Extra data to pass along to the terminal.
    function _addToBalanceOf(
        IJBDirectory _directory,
        uint256 _projectId,
        address _token,
        uint256 _amount,
        uint256 _decimals,
        string memory _memo,
        bytes memory _metadata
    ) internal virtual {
        // Find the terminal for the specified project.
        IJBPaymentTerminal _terminal = _directory.primaryTerminalOf(_projectId, _token);

        // There must be a terminal.
        if (_terminal == IJBPaymentTerminal(address(0))) revert TERMINAL_NOT_FOUND();

        // The amount's decimals must match the terminal's expected decimals.
        if (_terminal.decimalsForToken(_token) != _decimals) revert INCORRECT_DECIMAL_AMOUNT();

        // Approve the `_amount` of tokens from the destination terminal to transfer tokens from this contract.
        if (_token != JBTokens.ETH) IERC20(_token).safeApprove(address(_terminal), _amount);

        // If the token is ETH, send it in msg.value.
        uint256 _payableValue = _token == JBTokens.ETH ? _amount : 0;

        // Add to balance so tokens don't get issued.
        _terminal.addToBalanceOf{value: _payableValue}(_projectId, _amount, _token, _memo, _metadata);
    }
}
