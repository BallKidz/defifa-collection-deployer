// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/proxy/Clones.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import "@openzeppelin/contracts/utils/Strings.sol";
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBSplitsGroups.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol';
import '@jbx-protocol/juice-721-delegate/contracts/libraries/JBTiered721FundingCycleMetadataResolver.sol';
import './interfaces/IDefifaDeployer.sol';
import './structs/DefifaStoredOpsData.sol';
import './DefifaDelegate.sol';
import './DefifaGovernor.sol';
import './DefifaTokenUriResolver.sol';

/**
  @title
  DefifaDeployer

  @notice
  Deploys a Defifa game.

  @dev
  Adheres to -
  IDefifaDeployer: General interface for the generic controller methods in this contract that interacts with funding cycles and tokens according to the protocol's rules.
*/
contract DefifaDeployer is IDefifaDeployer, IERC721Receiver {
  using Strings for uint256;

  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INVALID_GAME_CONFIGURATION();
  error PHASE_ALREADY_QUEUED();
  error GAME_OVER();
  error UNEXPECTED_TERMINAL_CURRENCY();

  //*********************************************************************//
  // ----------------------- private constants ------------------------- //
  //*********************************************************************//

  /**
    @notice
    The ID of the project that takes fees upon distribution.
  */
  uint256 internal constant _PROTOCOL_FEE_PROJECT = 1;

  /**
    @notice
    Useful for the deploy flow to get memory management right.
  */
  uint256 internal constant _DEPLOY_BYTECODE_LENGTH = 13;

  //*********************************************************************//
  // ----------------------- internal proprties ------------------------ //
  //*********************************************************************//

  /**
    @notice
    Start time of the 2nd fc when re-configuring the fc.
  */
  mapping(uint256 => DefifaTimeData) internal _timesFor;

  /**
    @notice
    Operations variables for a game.

    @dev
    Includes the payment terminal being used, the distribution limit, and wether or not fees should be held.
  */
  mapping(uint256 => DefifaStoredOpsData) internal _opsFor;
  
  /** 
    @notice 
    This contract current nonce, used for the registry initialized at 1 since the first contract deployed is the delegate
  */
  uint256 internal _nonce = 1;

  //*********************************************************************//
  // ------------------------ public constants ------------------------- //
  //*********************************************************************//

  /**
    @notice
    The project ID relative to which splits are stored.

    @dev
    The owner of this project ID must give this contract operator permissions over the SET_SPLITS operation.
  */
  uint256 public constant override BALLKIDZ_PROJECT_ID = 369;

  /**
    @notice
    The domain relative to which splits are stored.

    @dev
    This could be any fixed number.
  */
  uint256 public constant override SPLIT_DOMAIN = 0;

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /**
    @notice 
    The original code for the Defifa delegate to base subsequent instances on.
   */
  address public immutable override delegateCodeOrigin;

  /**
    @notice 
    The original code for the Defifa governor to base subsequent instances on.
   */
  address public immutable override governorCodeOrigin;

  /**
    @notice 
    The original code for the Defifa token URI resolver to base subsequent instances on.
  */
  address public immutable override tokenUriResolverCodeOrigin;

  /**
    @notice
    The controller with which new projects should be deployed.
  */
  IJBController3_1 public immutable override controller;

  /**
    @notice
    The address that should be forwarded JBX accumulated in this contract from game fund distributions.
  */
  address public override immutable protocolFeeProjectTokenAccount;

  /** 
    @notice 
    The delegates registry. 
  */
  IJBDelegatesRegistry public immutable delegatesRegistry;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  function timesFor(uint256 _gameId) external view override returns (DefifaTimeData memory) {
    return _timesFor[_gameId];
  }

  function mintDurationOf(uint256 _gameId) external view override returns (uint256) {
    return _timesFor[_gameId].mintDuration;
  }

  function refundPeriodDurationOf(uint256 _gameId) external view override returns (uint256) {
    return _timesFor[_gameId].refundPeriodDuration;
  }

  function startOf(uint256 _gameId) external view override returns (uint256) {
    return _timesFor[_gameId].start;
  }

  function endOf(uint256 _gameId) external view override returns (uint256) {
    return _timesFor[_gameId].end;
  }

  function terminalOf(uint256 _gameId) external view override returns (IJBPaymentTerminal) {
    return _opsFor[_gameId].terminal;
  }

  function distributionLimit(uint256 _gameId) external view override returns (uint256) {
    return uint256(_opsFor[_gameId].distributionLimit);
  }

  /**
    @notice
    Returns the number of the game phase.

    @dev
    The game phase corresponds to the game's current funding cycle number.

    @param _gameId The ID of the game to get the phase number of.

    @return The game phase number.
  */
  function currentGamePhaseOf(uint256 _gameId) external view override returns (uint256) {
    // Get the project's current funding cycle along with its metadata.
    JBFundingCycle memory _currentFundingCycle = controller.fundingCycleStore().currentOf(_gameId);

    // The phase is the current funding cycle number.
    return _currentFundingCycle.number;
  }

  /**
    @notice
    Whether or not the next phase still needs queuing.

    @param _gameId The ID of the game to get the queue status of.

    @return Whether or not the next phase still needs queuing.
  */
  function nextPhaseNeedsQueueing(uint256 _gameId) external view override returns (bool) {
    // Get the project's current funding cycle along with its metadata.
    JBFundingCycle memory _currentFundingCycle = controller.fundingCycleStore().currentOf(_gameId);
    // Get the project's queued funding cycle along with its metadata.
    JBFundingCycle memory _queuedFundingCycle = controller.fundingCycleStore().queuedOf(_gameId);

    // If the configurations are the same and the game hasn't ended, queueing is still needed.
    return _currentFundingCycle.number != 4 && _currentFundingCycle.configuration == _queuedFundingCycle.configuration;
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
    @param _delegateCodeOrigin The code of the Defifa delegate.
    @param _governorCodeOrigin The code of the Defifa governor.
    @param _tokenUriResolverCodeOrigin The token URI resolver with which new projects should be deployed. 
    @param _controller The controller to use to launch the game from.
    @param _protocolFeeProjectTokenAccount The address that should be forwarded JBX accumulated in this contract from game fund distributions. 
    @param _delegatesRegistry The contract storing references to the deployer of each delegate.
  */
  constructor(
    address _delegateCodeOrigin,
    address _governorCodeOrigin,
    address _tokenUriResolverCodeOrigin,
    IJBController3_1 _controller,
    address _protocolFeeProjectTokenAccount,
    IJBDelegatesRegistry _delegatesRegistry
  ) {
    delegateCodeOrigin = _delegateCodeOrigin;
    governorCodeOrigin = _governorCodeOrigin;
    tokenUriResolverCodeOrigin = _tokenUriResolverCodeOrigin;
    controller = _controller;
    protocolFeeProjectTokenAccount = _protocolFeeProjectTokenAccount;
    delegatesRegistry = _delegatesRegistry;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
    @notice
    Launches a new project with a Defifa data source attached.

    @param _launchProjectData Data necessary to fulfill the transaction to launch a project.

    @return gameId The ID of the newly configured game.
    @return governor The address that governs the game.
  */
  function launchGameWith(
    DefifaLaunchProjectData memory _launchProjectData
  ) external override returns (uint256 gameId, IDefifaGovernor governor) {
    // Start minting right away if a start time isn't provided.
    if (_launchProjectData.start == 0) _launchProjectData.start = uint48(block.timestamp);

    // Make sure the provided gameplay timestamps are sequential.
    if (
      _launchProjectData.start - _launchProjectData.refundPeriodDuration - _launchProjectData.mintDuration < block.timestamp ||
      _launchProjectData.end < _launchProjectData.start
    ) revert INVALID_GAME_CONFIGURATION();

    // Get the game ID, optimistically knowing it will be one greater than the current count.
    gameId = controller.projects().count() + 1;

    {
      // Store the timestamps that'll define the game phases.
      _timesFor[gameId] = DefifaTimeData({
        mintDuration: _launchProjectData.mintDuration,
        refundPeriodDuration: _launchProjectData.refundPeriodDuration,
        start: _launchProjectData.start,
        end: _launchProjectData.end
      });

      // Store the terminal, distribution limit, and hold fees flag.
      _opsFor[gameId] = DefifaStoredOpsData({
        terminal:_launchProjectData.terminal,
        distributionLimit: _launchProjectData.distributionLimit,
        token: _launchProjectData.token
      });

      if (_launchProjectData.splits.length != 0) {
        // Store the splits. They'll be used when queueing phase 2.
        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
        // Add a split for the Ballkidz fee.
        _launchProjectData.splits[_launchProjectData.splits.length] = JBSplit({
          preferClaimed: false,
          preferAddToBalance: false,
          percent: JBConstants.SPLITS_TOTAL_PERCENT / 20,
          projectId: BALLKIDZ_PROJECT_ID,
          beneficiary: _launchProjectData.ballkidzFeeProjectTokenAccount,
          lockedUntil: 0,
          allocator: IJBSplitAllocator(address(0))
        });
        _groupedSplits[0] = JBGroupedSplits({group: gameId, splits: _launchProjectData.splits});
        // This contract must have SET_SPLITS operator permissions.
        controller.splitsStore().set(BALLKIDZ_PROJECT_ID, SPLIT_DOMAIN, _groupedSplits);
      }
    }
    
    // Keep track of the number of tiers.
    uint256 _numberOfTiers = _launchProjectData.tiers.length;  

    // Create the standard tiers struct that will be populated from the defifa tiers.
    JB721TierParams[] memory _delegateTiers = new JB721TierParams[](_launchProjectData.tiers.length);

    // Group all the tier names together.
    string[] memory _tierNames = new string[](_launchProjectData.tiers.length);

    // Keep a reference to the tier being iterated on.
    DefifaTierParams memory _defifaTier;

    // Create the delegate tiers from the Defifa tiers.
    for (uint256 _i; _i < _numberOfTiers;) {
      _defifaTier = _launchProjectData.tiers[_i];

      // Set the tier.
      _delegateTiers[_i] = JB721TierParams({
        contributionFloor: _defifaTier.price,
        initialQuantity: 999_999_999, // The max allowed value.
        votingUnits: 1,
        lockedUntil: 0,
        reservedRate: _defifaTier.reservedRate,
        reservedTokenBeneficiary: _defifaTier.reservedTokenBeneficiary,
        royaltyRate: _defifaTier.royaltyRate,
        royaltyBeneficiary: _defifaTier.royaltyBeneficiary,
        encodedIPFSUri: _defifaTier.encodedIPFSUri,
        category: 1,
        allowManualMint: false,
        shouldUseReservedTokenBeneficiaryAsDefault: _defifaTier.shouldUseReservedTokenBeneficiaryAsDefault, 
        shouldUseRoyaltyBeneficiaryAsDefault: false,
        transfersPausable: false
      });

      // Set the name.
      _tierNames[_i] = _defifaTier.name;

      unchecked {
        ++_i;
      }
    }

    JB721PricingParams memory _pricingParams = JB721PricingParams({
        tiers: _delegateTiers,
        currency: _launchProjectData.terminal.currencyForToken(_launchProjectData.token),
        decimals: _launchProjectData.terminal.decimalsForToken(_launchProjectData.token),
        prices: IJBPrices(address(0))
      });

    // Clone and initialize the new delegate with a new token uri resolver.
    DefifaDelegate _delegate = DefifaDelegate(Clones.clone(delegateCodeOrigin));
    DefifaTokenUriResolver _uriResolver = DefifaTokenUriResolver(Clones.clone(tokenUriResolverCodeOrigin));
    _delegate.initialize(
      gameId,
      controller.directory(),
      _launchProjectData.name,
      string.concat('DEFIFA ', gameId.toString()),
      controller.fundingCycleStore(),
      _launchProjectData.baseUri,
      _uriResolver,
      _launchProjectData.contractUri,
      _pricingParams,
      _launchProjectData.store,
      JBTiered721Flags({
          preventOverspending: true,
          lockReservedTokenChanges: false,
          lockVotingUnitChanges: false,
          lockManualMintingChanges: false
      })
    );
    _uriResolver.initialize(_delegate, _tierNames);

    // Make sure the provided terminal accepts the same currency as this game is being played in.
    if (!_launchProjectData.terminal.acceptsToken(_launchProjectData.token, gameId)) revert UNEXPECTED_TERMINAL_CURRENCY();

    // Queue the first phase of the game.
    _queuePhase1(_launchProjectData, address(_delegate));

    // Clone and initialize the new governor.
     governor = IDefifaGovernor(Clones.clone(governorCodeOrigin));
     governor.initialize(_delegate, _launchProjectData.end, _launchProjectData.votingPeriod);

    // Transfer ownership to the specified owner.
    _delegate.transferOwnership(address(governor));

    // Add the delegate to the registry, contract nonce starts at 1
    delegatesRegistry.addDelegate(address(this), _nonce);

    // Add three to the nonce because 3 contracts were deployed during this launch process.
    _nonce = _nonce + 3;
  }

  /**
    @notice
    Queues the funding cycle that represents the next phase of the game, if it isn't queued already.

    @param _gameId The ID of the project having funding cycles reconfigured.

    @return configuration The configuration of the funding cycle that was successfully reconfigured.
  */
  function queueNextPhaseOf(uint256 _gameId)
    external
    override
    returns (uint256 configuration)
  {
    // Get the project's current funding cycle along with its metadata.
    (JBFundingCycle memory _currentFundingCycle, JBFundingCycleMetadata memory _metadata) = controller
      .currentFundingCycleOf(_gameId);

    // There are only 4 phases.
    if (_currentFundingCycle.number >= 4) revert GAME_OVER();

    // Get the project's queued funding cycle.
    (JBFundingCycle memory queuedFundingCycle, ) = controller.queuedFundingCycleOf(_gameId);

    // Make sure the next game phase isn't already queued.
    if (_currentFundingCycle.configuration != queuedFundingCycle.configuration)
      revert PHASE_ALREADY_QUEUED();

    // Queue the next phase of the game.
    if (_currentFundingCycle.number == 1) return _queuePhase2(_gameId, _metadata.dataSource);
    else if (_currentFundingCycle.number == 2) return _queuePhase3(_gameId, _metadata.dataSource);
    else return _queuePhase4(_gameId, _metadata.dataSource);
  }

  /** 
    @notice
    Move accumulated protocol project tokens from paying fees into the recipient. 

    @dev
    This contract accumulated JBX as games distribute payouts.
  */
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

  /**
    @notice
    Allows this contract to receive 721s.
  */
  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
     return IERC721Receiver.onERC721Received.selector;
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  /**
    @notice
    Launches a Defifa project with phase 1 configured.

    @param _launchProjectData Project data used for launching a Defifa game.
    @param _dataSource The address of the Defifa data source.
  */
  function _queuePhase1(DefifaLaunchProjectData memory _launchProjectData, address _dataSource)
    internal
  {
    // Initialize the terminal array .
    IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
    _terminals[0] = _launchProjectData.terminal;

    // Launch the project with params for phase 1 of the game.
    controller.launchProjectFor(
      // Project is owned by this contract.
      address(this),
      _launchProjectData.projectMetadata,
      JBFundingCycleData ({
        duration: _launchProjectData.mintDuration,
        // Don't mint project tokens.
        weight: 0,
        discountRate: 0,
        ballot: IJBFundingCycleBallot(address(0))
      }),
      JBFundingCycleMetadata ({
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
        metadata:  JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
          JBTiered721FundingCycleMetadata({
            pauseTransfers: false,
            // Reserved tokens can't be minted during this funding cycle.
            pauseMintingReserves: true
          })
        )
      }),
      _launchProjectData.start - _launchProjectData.mintDuration - _launchProjectData.refundPeriodDuration,
      new JBGroupedSplits[](0),
      new JBFundAccessConstraints[](0),
      _terminals,
      'Defifa game phase 1.'
    );
  }

  /**
    @notice
    Gets reconfiguration data for phase 2 of the game.

    @dev
    Phase 2 freezes mints, but continues to allow refund redemptions.

    @param _gameId The ID of the project that's being reconfigured.
    @param _dataSource The data source to use.

    @return configuration The configuration of the funding cycle that was successfully reconfigured.
  */
  function _queuePhase2(uint256 _gameId, address _dataSource)
    internal
    returns (uint256 configuration)
  {

    // Get a reference to the time data.
    DefifaTimeData memory _times = _timesFor[_gameId];

    return
      controller.reconfigureFundingCyclesOf(
        _gameId,
        JBFundingCycleData ({
          duration: _times.refundPeriodDuration,
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
          // Set a metadata of 1 to impose token non-transferability.
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
        'Defifa game phase 2.'
      );
  }

  /**
    @notice
    Gets reconfiguration data for phase 3 of the game.

    @dev
    Phase 3 freezes the treasury and activates the pre-programmed distribution limit to the specified splits.

    @param _gameId The ID of the project that's being reconfigured.
    @param _dataSource The data source to use.

    @return configuration The configuration of the funding cycle that was successfully reconfigured.
  */
  function _queuePhase3(uint256 _gameId, address _dataSource)
    internal
    returns (uint256 configuration)
  {
    // Get a reference to the terminal being used by the project.
    DefifaStoredOpsData memory _ops = _opsFor[_gameId];

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
    JBSplit[] memory _splits =  controller.splitsStore().splitsOf(BALLKIDZ_PROJECT_ID, SPLIT_DOMAIN, _gameId);

    // Make a group split for ETH payouts.
    JBGroupedSplits[] memory _groupedSplits;

    if (_splits.length != 0) {
      _groupedSplits = new JBGroupedSplits[](1);
      uint256 _group = _ops.token == JBTokens.ETH ? JBSplitsGroups.ETH_PAYOUT : uint160(_ops.token);
      _groupedSplits[0] = JBGroupedSplits({group: _group, splits: _splits});
    }
    else {
      _groupedSplits = new JBGroupedSplits[](0);
    }

    // Get a reference to the time data.
    DefifaTimeData memory _times = _timesFor[_gameId];

    return
      controller.reconfigureFundingCyclesOf(
        _gameId,
        JBFundingCycleData ({
          duration: _times.end - _times.start,
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
          redemptionRate: 0,
          ballotRedemptionRate: 0,
          // No more payments.
          pausePay: true,
          pauseDistributions: false,
          // No redemptions.
          pauseRedeem: true,
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
              pauseMintingReserves: false
            })
          )
        }),
        0, // mustStartAtOrAfter should be ASAP
         _groupedSplits,
        fundAccessConstraints,
        'Defifa game phase 3.'
      );
  }

  /**
    @notice
    Gets reconfiguration data for phase 4 of the game.

    @dev
    Phase 4 removes the trade deadline and opens up redemptions.

    @param _gameId The ID of the project that's being reconfigured.
    @param _dataSource The data source to use.

    @return configuration The configuration of the funding cycle that was successfully reconfigured.
  */
  function _queuePhase4(uint256 _gameId, address _dataSource) internal returns (uint256 configuration) {
    return
      controller.reconfigureFundingCyclesOf(
        _gameId,
        JBFundingCycleData ({
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
          // Transferability unlocked.
          metadata: JBTiered721FundingCycleMetadataResolver.packFundingCycleGlobalMetadata(
            JBTiered721FundingCycleMetadata({
              pauseTransfers: false,
              pauseMintingReserves: false
            })
          )
        }),
        0, // mustStartAtOrAfter should be ASAP
        new JBGroupedSplits[](0),
        new JBFundAccessConstraints[](0),
        'Defifa game phase 4.'
      );
  }
}
