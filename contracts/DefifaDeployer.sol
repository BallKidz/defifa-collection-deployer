// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1.sol";
import "@jbx-protocol/juice-721-delegate/contracts/libraries/JBTiered721FundingCycleMetadataResolver.sol";
import "./enums/DefifaGamePhase.sol";
import "./interfaces/IDefifaDeployer.sol";
import "./interfaces/IDefifaGamePhaseReporter.sol";
import "./interfaces/IDefifaGamePotReporter.sol";
import "./structs/DefifaDistributionOpsData.sol";
import "./DefifaDelegate.sol";
import "./DefifaTokenUriResolver.sol";

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

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error GAME_OVER();
    error INVALID_FEE_PERCENT();
    error INVALID_GAME_CONFIGURATION();
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

    /// @notice Start time of the 2nd fc when re-configuring the fc.
    mapping(uint256 => DefifaTimeData) internal _timesFor;

    /// @notice Distribution operations variables for a game.
    /// @dev Includes the payment terminal being used, the distribution limit, and wether or not fees should be held.
    mapping(uint256 => DefifaDistributionOpsData) internal _distributionOpsOf;

    /// @notice This contract current nonce, used for the registry initialized at 1 since the first contract deployed is the delegate
    uint256 internal _nonce = 1;

    /// @notice If each game has been set to no contest.
    mapping(uint256 => bool) internal _noContestIsSet;

    //*********************************************************************//
    // ------------------------ public constants ------------------------- //
    //*********************************************************************//

    /// @notice The domain relative to which splits are stored.
    /// @dev This could be any fixed number.
    uint256 public constant override SPLIT_DOMAIN = 0;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The project ID relative to which splits are stored.
    /// @dev The owner of this project ID must give this contract operator permissions over the SET_SPLITS operation.
    uint256 public immutable override ballkidzProjectId;

    /// @notice The original code for the Defifa delegate to base subsequent instances on.
    address public immutable override delegateCodeOrigin;

    /// @notice The original code for the Defifa governor to base subsequent instances on.
    address public immutable override governorCodeOrigin;

    /// @notice The original code for the Defifa token URI resolver to base subsequent instances on.
    address public immutable override tokenUriResolverCodeOrigin;

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

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The game times.
    /// @param _gameId The ID of the game for which the game times apply.
    /// @return The game times.
    function timesFor(uint256 _gameId) external view override returns (DefifaTimeData memory) {
        return _timesFor[_gameId];
    }

    /// @notice The distribution ops.
    /// @param _gameId The ID of the game for which the distribution ops apply.
    /// @return The distribution ops.
    function distributionOpsOf(uint256 _gameId) external view override returns (DefifaDistributionOpsData memory) {
        return _distributionOpsOf[_gameId];
    }

    /// @notice The current pot the game is being played with.
    /// @param _gameId The ID of the game for which the pot apply.
    /// @return The game's pot amount, as a fixed point number.
    /// @return The token address the game's pot is measured in.
    /// @return The number of decimals included in the amount.
    function currentGamePotOf(uint256 _gameId) external view returns (uint256, address, uint256) {
        // Get a reference to the distribution ops being used by the project.
        DefifaDistributionOpsData memory _ops = _distributionOpsOf[_gameId];

        // Get a reference to the terminal.
        address _terminal = address(_ops.terminal);

        // Get the current balance.
        uint256 _pot = IJBPayoutRedemptionPaymentTerminal3_1(_terminal).store().currentOverflowOf(
            IJBSingleTokenPaymentTerminal(_terminal), _gameId
        );

        return (
            _pot, IJBSingleTokenPaymentTerminal(_terminal).token(), IJBSingleTokenPaymentTerminal(_terminal).decimals()
        );
    }

    /// @notice Returns the number of the game phase.
    /// @dev The game phase corresponds to the game's current funding cycle number.
    /// @param _gameId The ID of the game to get the phase number of.
    /// @return The game phase.
    function currentGamePhaseOf(uint256 _gameId) external view override returns (DefifaGamePhase) {
        // Get the project's current funding cycle along with its metadata.
        (JBFundingCycle memory _currentFundingCycle, JBFundingCycleMetadata memory _metadata) =
            controller.currentFundingCycleOf(_gameId);

        if (_currentFundingCycle.number == 0) return DefifaGamePhase.COUNTDOWN;
        if (_currentFundingCycle.number == 1) return DefifaGamePhase.MINT;
        if (_noContestIsSet[_gameId]) return DefifaGamePhase.NO_CONTEST;
        if (_noContestInevitable(_gameId, _currentFundingCycle)) return DefifaGamePhase.NO_CONTEST_INEVITABLE;
        if (_currentFundingCycle.number == 2 && _timesFor[_gameId].refundDuration != 0) return DefifaGamePhase.REFUND;
        if (IDefifaDelegate(_metadata.dataSource).redemptionWeightIsSet()) return DefifaGamePhase.COMPLETE;
        return DefifaGamePhase.SCORING;
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
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _delegateCodeOrigin The code of the Defifa delegate.
    /// @param _governorCodeOrigin The code of the Defifa governor.
    /// @param _tokenUriResolverCodeOrigin The token URI resolver with which new projects should be deployed.
    /// @param _controller The controller to use to launch the game from.
    /// @param _delegatesRegistry The contract storing references to the deployer of each delegate.
    /// @param _protocolFeeProjectTokenAccount The address that should be forwarded JBX accumulated in this contract from game fund distributions.
    /// @param _ballkidzProjectId The ID of the project that should take the fee from the games.
    /// @param _owner The address that can change the fees.
    constructor(
        address _delegateCodeOrigin,
        address _governorCodeOrigin,
        address _tokenUriResolverCodeOrigin,
        IJBController3_1 _controller,
        IJBDelegatesRegistry _delegatesRegistry,
        address _protocolFeeProjectTokenAccount,
        uint256 _ballkidzProjectId,
        address _owner
    ) {
        delegateCodeOrigin = _delegateCodeOrigin;
        governorCodeOrigin = _governorCodeOrigin;
        tokenUriResolverCodeOrigin = _tokenUriResolverCodeOrigin;
        controller = _controller;
        protocolFeeProjectTokenAccount = _protocolFeeProjectTokenAccount;
        delegatesRegistry = _delegatesRegistry;
        ballkidzProjectId = _ballkidzProjectId;

        _transferOwnership(_owner);
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Launches a new game owned by this contract with a DefifaDelegate attached.
    /// @param _launchProjectData Data necessary to fulfill the transaction to launch a game.
    /// @return gameId The ID of the newly configured game.
    /// @return governor The address that governs the game.
    function launchGameWith(DefifaLaunchProjectData memory _launchProjectData)
        external
        override
        returns (uint256 gameId, IDefifaGovernor governor)
    {
        // Start the game right after the mint and refund durations if it isnt provided.
        if (_launchProjectData.start == 0) {
            _launchProjectData.start =
                uint48(block.timestamp + _launchProjectData.mintDuration + _launchProjectData.refundDuration);
        }
        // Start minting right away if a start time isn't provided.
        else if (
            _launchProjectData.mintDuration == 0
                && _launchProjectData.start > block.timestamp + _launchProjectData.refundDuration
        ) {
            _launchProjectData.mintDuration =
                uint48(_launchProjectData.start - (block.timestamp + _launchProjectData.refundDuration));
        }

        // Make sure the provided gameplay timestamps are sequential and that there is a mint duration.
        if (
            _launchProjectData.mintDuration == 0
                || _launchProjectData.start
                    > block.timestamp + _launchProjectData.refundDuration + _launchProjectData.mintDuration
        ) revert INVALID_GAME_CONFIGURATION();

        // Get the game ID, optimistically knowing it will be one greater than the current count.
        gameId = controller.projects().count() + 1;

        {
            // Store the timestamps that'll define the game phases.
            _timesFor[gameId] = DefifaTimeData({
                mintDuration: _launchProjectData.mintDuration,
                refundDuration: _launchProjectData.refundDuration,
                start: _launchProjectData.start
            });

            // Store the terminal and distribution limit.
            _distributionOpsOf[gameId] = DefifaDistributionOpsData({
                terminal: _launchProjectData.terminal,
                distributionLimit: _launchProjectData.distributionLimit,
                token: _launchProjectData.token
            });

            // Keep a reference to the number of splits.
            uint256 _numberOfSplits = _launchProjectData.splits.length;

            if (_numberOfSplits != 0) {
                // Keep a reference to the split percent.
                uint256 _feePercent = JBConstants.SPLITS_TOTAL_PERCENT / feeDivisor;

                // Keep a reference to the total percent of splits being set.
                uint256 _totalSplitPercent;
                for (uint256 _i; _i < _numberOfSplits;) {
                    _totalSplitPercent += _launchProjectData.splits[_i].percent;
                    unchecked {
                        ++_i;
                    }
                }

                // Make sure the splits leave room for the fee.
                if (_totalSplitPercent != JBConstants.SPLITS_TOTAL_PERCENT - _feePercent) {
                    revert SPLITS_DONT_ADD_UP();
                }

                // Add a split for the Ballkidz fee.
                _launchProjectData.splits[_launchProjectData.splits.length] = JBSplit({
                    preferClaimed: false,
                    preferAddToBalance: false,
                    percent: _feePercent,
                    projectId: ballkidzProjectId,
                    beneficiary: _launchProjectData.ballkidzFeeProjectTokenAccount,
                    lockedUntil: 0,
                    allocator: IJBSplitAllocator(address(0))
                });

                // Store the splits. They'll be used when queueing phase 2.
                JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
                _groupedSplits[0] = JBGroupedSplits({group: gameId, splits: _launchProjectData.splits});

                // This contract must have SET_SPLITS operator permissions.
                controller.splitsStore().set(ballkidzProjectId, SPLIT_DOMAIN, _groupedSplits);
            }
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
        IJBTokenUriResolver _uriResolver = _launchProjectData.defaultTokenUriResolver != IJBTokenUriResolver(address(0))
            ? _launchProjectData.defaultTokenUriResolver
            : DefifaTokenUriResolver(Clones.clone(tokenUriResolverCodeOrigin));

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
            _defaultVotingDelegate: _launchProjectData.defaultVotingDelegate,
            _tierNames: _tierNames
        });

        // Initialize the fallback default uri resolver if needed.
        if (_launchProjectData.defaultTokenUriResolver == IJBTokenUriResolver(address(0))) {
            DefifaTokenUriResolver(address(_uriResolver)).initialize({_delegate: _delegate});
        }

        // Make sure the provided terminal accepts the same currency as this game is being played in.
        if (!_launchProjectData.terminal.acceptsToken(_launchProjectData.token, gameId)) {
            revert UNEXPECTED_TERMINAL_CURRENCY();
        }

        // Queue the mint phase of the game.
        _queueMintPhase(_launchProjectData, address(_delegate));

        // Clone and initialize the new governor.
        governor = IDefifaGovernor(Clones.clone(governorCodeOrigin));
        governor.initializeGame({
            _gameId: gameId,
            _attestationStartTime: uint256(_launchProjectData.votingStartTime),
            _attestationGracePeriod: uint256(_launchProjectData.votingPeriod)
        });

        // Transfer ownership to the specified owner.
        _delegate.transferOwnership(address(governor));

        // Add the delegate to the registry, contract nonce starts at 1
        delegatesRegistry.addDelegate(address(this), _nonce);

        // Add three to the nonce because 3 contracts were deployed during this launch process.
        _nonce = _nonce + 3;

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
        if (_currentFundingCycle.number == 1 && _timesFor[_gameId].refundDuration != 0) {
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

    /// @notice Allow this contract's owner to change the publishing fee.
    /// @dev The max fee is %5.
    /// @param _percent The percent fee to charge.
    function changeFee(uint256 _percent) external onlyOwner {
        // Make sure the fee is not greater than 5%.
        if (_percent > 5) revert INVALID_FEE_PERCENT();

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
                duration: _launchProjectData.mintDuration,
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
            _launchProjectData.start - _launchProjectData.mintDuration - _launchProjectData.refundDuration,
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
        // Get a reference to the time data.
        DefifaTimeData memory _times = _timesFor[_gameId];

        return controller.reconfigureFundingCyclesOf(
            _gameId,
            JBFundingCycleData({
                duration: _times.refundDuration,
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
        // Get a reference to the terminal being used by the project.
        DefifaDistributionOpsData memory _ops = _distributionOpsOf[_gameId];

        // Set fund access constraints.
        JBFundAccessConstraints[] memory fundAccessConstraints = new JBFundAccessConstraints[](1);
        fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: _ops.terminal,
            token: _ops.token,
            distributionLimit: _ops.distributionLimit,
            distributionLimitCurrency: _ops.terminal.currencyForToken(_ops.token),
            overflowAllowance: 0,
            overflowAllowanceCurrency: 0
        });

        // Fetch splits.
        JBSplit[] memory _splits = controller.splitsStore().splitsOf(ballkidzProjectId, SPLIT_DOMAIN, _gameId);

        // Make a group split for ETH payouts.
        JBGroupedSplits[] memory _groupedSplits;

        if (_splits.length != 0) {
            _groupedSplits = new JBGroupedSplits[](1);
            uint256 _group = _ops.token == JBTokens.ETH ? JBSplitsGroups.ETH_PAYOUT : uint160(_ops.token);
            _groupedSplits[0] = JBGroupedSplits({group: _group, splits: _splits});
        } else {
            _groupedSplits = new JBGroupedSplits[](0);
        }

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
            _groupedSplits,
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
}
