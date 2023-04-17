// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Checkpoints.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBFundingCycleMetadataResolver.sol';
import '@jbx-protocol/juice-721-delegate/contracts/abstract/JB721Delegate.sol';
import '@jbx-protocol/juice-721-delegate/contracts/libraries/JBTiered721FundingCycleMetadataResolver.sol';

import './interfaces/IDefifaDelegate.sol';

/** 
  @title
  DefifaDelegate

  @notice
  Defifa specific 721 tiered delegate.

  @dev
  Adheres to -
  IDefifaDelegate: General interface for the methods in this contract that interact with the blockchain's state according to the protocol's rules.

  @dev
  Inherits from -
  JB721TieredGovernance: A generic tiered 721 delegate.
*/
contract DefifaDelegate is IDefifaDelegate, JB721Delegate, Ownable, IERC2981 {
  using Checkpoints for Checkpoints.History;

  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error BLOCK_NOT_YET_MINED();
  error DELEGATE_ADDRESS_ZERO();
  error GAME_ISNT_OVER_YET();
  error INVALID_TIER_ID();
  error INVALID_REDEMPTION_WEIGHTS();
  error NOTHING_TO_CLAIM();
  error NOTHING_TO_MINT();
  error WRONG_CURRENCY();
  error NOT_AVAILABLE();
  error OVERSPENDING();
  error PRICING_RESOLVER_CHANGES_PAUSED();
  error RESERVED_TOKEN_MINTING_PAUSED();
  error TRANSFERS_PAUSED();

  //*********************************************************************//
  // -------------------- private constant properties ------------------ //
  //*********************************************************************//

  /** 
    @notice
    The funding cycle number of the mint phase. 
  */
  uint256 private constant _MINT_GAME_PHASE = 1;

  /** 
    @notice
    The funding cycle number of the end game phase. 
  */
  uint256 private constant _END_GAME_PHASE = 4;

  //*********************************************************************//
  // --------------------- public constant properties ------------------ //
  //*********************************************************************//

  /** 
    @notice 
    The total weight that can be divided among tiers.
  */
  uint256 public constant override TOTAL_REDEMPTION_WEIGHT = 1_000_000_000;

  //*********************************************************************//
  // -------------------- internal stored properties ------------------- //
  //*********************************************************************//

  /** 
    @notice 
    The redemption weight for each tier.

    @dev
    Tiers are limited to ID 128
  */
  uint256[128] internal _tierRedemptionWeights;

  /**
    @notice
    The amount that has been redeemed.
   */
  uint256 internal _amountRedeemed;

  /**
    @notice
    The amount of tokens that have been redeemed from a tier, refunds are not counted
  */
  mapping(uint256 => uint256) internal _redeemedFromTier;

  /**
    @notice
    The delegation status for each address and for each tier.

    _delegator The delegator.
    _tierId The ID of the tier being delegated.
  */
  mapping(address => mapping(uint256 => address)) internal _tierDelegation;

  /**
    @notice
    The delegation checkpoints for each address and for each tier.

    _delegator The delegator.
    _tierId The ID of the tier being delegated.
  */
  mapping(address => mapping(uint256 => Checkpoints.History)) internal _delegateTierCheckpoints;

  /**
    @notice
    The total delegation status for each tier.

    _tierId The ID of the tier being delegated.
  */
  mapping(uint256 => Checkpoints.History) internal _totalTierCheckpoints;

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
    @notice
    The address of the origin 'JBTiered721Delegate', used to check in the init if the contract is the original or not
  */
  address public override codeOrigin;

  /**
    @notice
    The contract that stores and manages the NFT's data.
  */
  IJBTiered721DelegateStore public override store;

  /**
    @notice
    The contract storing all funding cycle configurations.
  */
  IJBFundingCycleStore public override fundingCycleStore;

  /** 
    @notice
    The currency that is accepted when minting tier NFTs. 
  */
  uint256 public override pricingCurrency;

  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /** 
    @notice
    The name of the NFT.

    @return The name of the NFT.
  */
  function name() public view override(ERC721, IDefifaDelegate) returns (string memory) {
    return super.name();
  }

  /** 
    @notice
    Returns the URI where contract metadata can be found. 

    @return The contract's metadata URI.
  */
  function contractURI() external view virtual override returns (string memory) {
    return store.contractUriOf(address(this));
  }

  /** 
    @notice
    The redemption weight for each tier.

    @return The array of weights, indexed by tier.
  */
  function tierRedemptionWeights() external view override returns (uint256[128] memory) {
    return _tierRedemptionWeights;
  }

  /**
    @notice
    Returns the delegate of an account for specific tier.

    @param _account The account to check for a delegate of.
    @param _tier the tier to check within.
  */
  function getTierDelegate(
    address _account,
    uint256 _tier
  ) external view override returns (address) {
    return _tierDelegation[_account][_tier];
  }

  /**
    @notice
    Returns the current voting power of an address for a specific tier.

    @param _account The address to check.
    @param _tier The tier to check within.
  */
  function getTierVotes(address _account, uint256 _tier) external view override returns (uint256) {
    return _delegateTierCheckpoints[_account][_tier].latest();
  }

  /**
    @notice
    Returns the past voting power of a specific address for a specific tier.

    @param _account The address to check.
    @param _tier The tier to check within.
    @param _blockNumber the blocknumber to check the voting power at.
  */
  function getPastTierVotes(
    address _account,
    uint256 _tier,
    uint256 _blockNumber
  ) external view override returns (uint256) {
    return _delegateTierCheckpoints[_account][_tier].getAtBlock(_blockNumber);
  }

  /**
    @notice
    Returns the total amount of voting power that exists for a tier.

    @param _tier The tier to check.
  */
  function getTierTotalVotes(uint256 _tier) external view override returns (uint256) {
    return _totalTierCheckpoints[_tier].latest();
  }

  /**
    @notice
    Returns the total amount of voting power that exists for a tier.

    @param _tier The tier to check.
    @param _blockNumber The blocknumber to check the total voting power at.
  */
  function getPastTierTotalVotes(
    uint256 _tier,
    uint256 _blockNumber
  ) external view override returns (uint256) {
    return _totalTierCheckpoints[_tier].getAtBlock(_blockNumber);
  }

  /**
    @notice
    The first owner of each token ID, which corresponds to the address that originally contributed to the project to receive the NFT.

    @param _tokenId The ID of the token to get the first owner of.

    @return The first owner of the token.
  */
  function firstOwnerOf(uint256 _tokenId) external view override returns (address) {
    // Get a reference to the first owner.
    address _storedFirstOwner = store.firstOwnerOf(address(this), _tokenId);

    // If the stored first owner is set, return it.
    if (_storedFirstOwner != address(0)) return _storedFirstOwner;

    // Otherwise, the first owner must be the current owner.
    return _owners[_tokenId];
  }

  /**
    @notice 
    Royalty info conforming to EIP-2981.

    @param _tokenId The ID of the token that the royalty is for.
    @param _salePrice The price being paid for the token.

    @return The address of the royalty's receiver.
    @return The amount of the royalty.
  */
  function royaltyInfo(
    uint256 _tokenId,
    uint256 _salePrice
  ) external view override returns (address, uint256) {
    return store.royaltyInfo(address(this), _tokenId, _salePrice);
  }

  //*********************************************************************//
  // -------------------------- public views --------------------------- //
  //*********************************************************************//

  /** 
    @notice 
    The total number of tokens owned by the given owner across all tiers. 

    @param _owner The address to check the balance of.

    @return balance The number of tokens owners by the owner across all tiers.
  */
  function balanceOf(address _owner) public view override returns (uint256 balance) {
    return store.balanceOf(address(this), _owner);
  }

  /** 
    @notice
    The metadata URI of the provided token ID.

    @dev
    Defer to the tokenUriResolver if set, otherwise, use the tokenUri set with the token's tier.

    @param _tokenId The ID of the token to get the tier URI for. 

    @return The token URI corresponding with the tier or the tokenUriResolver URI.
  */
  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    // Use the resolver.
    return store.tokenUriResolverOf(address(this)).getUri(_tokenId);
  }

  /** 
    @notice
    The cumulative weight the given token IDs have in redemptions compared to the `_totalRedemptionWeight`. 

    @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.

    @return cumulativeWeight The weight.
  */
  function redemptionWeightOf(
    uint256[] memory _tokenIds,
    JBRedeemParamsData calldata
  ) public view virtual override returns (uint256 cumulativeWeight) {
    // If the game is over, set the weight based on the scorecard results.
    // Keep a reference to the number of tokens being redeemed.
    uint256 _tokenCount = _tokenIds.length;

    for (uint256 _i; _i < _tokenCount; ) {
      // Calculate what percentage of the tier redemption amount a single token counts for.
      cumulativeWeight += redemptionWeightOf(_tokenIds[_i]);

      unchecked {
        ++_i;
      }
    }
  }

  /** 
    @notice
    The weight the given token ID have in redemptions. 

    @param _tokenId The ID of the token to get the redemption weight of.

    @return The weight.
  */
  function redemptionWeightOf(uint256 _tokenId) public view override returns (uint256) {
    // Keep a reference to the token's tier ID.
    uint256 _tierId = store.tierIdOfToken(_tokenId);

    // Keep a reference to the tier.
    JB721Tier memory _tier = store.tier(address(this), _tierId);

    // Get the tier Id.
    uint256 _weight = _tierRedemptionWeights[_tierId - 1];

    // If there's no weight there's nothing to redeem.
    if (_weight == 0) return 0;

    // If no tiers were minted, nothing to redeem.
    if (_tier.initialQuantity - _tier.remainingQuantity == 0) return 0;
    // TODO allow anyone to move leftover funds from unminted winning tiers to ballkids.

    // Calculate what percentage of the tier redemption amount a single token counts for.
    return
      // Tier's are 1 indexed and are stored 0 indexed.
      _weight / (_tier.initialQuantity - _tier.remainingQuantity + _redeemedFromTier[_tierId]);
  }

  /** 
    @notice
    The cumulative weight that all token IDs have in redemptions. 

    @return The total weight.
  */
  function totalRedemptionWeight(
    JBRedeemParamsData calldata
  ) public view virtual override returns (uint256) {
    // Set the total weight as the total scorecard weight.
    return TOTAL_REDEMPTION_WEIGHT;
  }

  /**
    @notice 
    Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem.

    @param _data The Juicebox standard project redemption data.

    @return reclaimAmount The amount that should be reclaimed from the treasury.
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
  */
  function redeemParams(
    JBRedeemParamsData calldata _data
  )
    public
    view
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      JBRedemptionDelegateAllocation[] memory delegateAllocations
    )
  {
    // Make sure fungible project tokens aren't being redeemed too.
    if (_data.tokenCount > 0) revert UNEXPECTED_TOKEN_REDEEMED();

    // Check the 4 bytes interfaceId and handle the case where the metadata was not intended for this contract
    // Skip 32 bytes reserved for generic extension parameters.
    if (
      _data.metadata.length < 36 ||
      bytes4(_data.metadata[32:36]) != type(IJB721Delegate).interfaceId
    ) revert INVALID_REDEMPTION_METADATA();

    // Set the only delegate allocation to be a callback to this contract.
    delegateAllocations = new JBRedemptionDelegateAllocation[](1);
    delegateAllocations[0] = JBRedemptionDelegateAllocation(this, 0);

    // Decode the metadata
    (, , uint256[] memory _decodedTokenIds) = abi.decode(
      _data.metadata,
      (bytes32, bytes4, uint256[])
    );

    // If the game is in its minting phase, reclaim Amount is the same as it cost to mint.
    if (fundingCycleStore.currentOf(_data.projectId).number == _MINT_GAME_PHASE) {
      // Keep a reference to the number of tokens.
      uint256 _numberOfTokenIds = _decodedTokenIds.length;

      for (uint256 _i; _i < _numberOfTokenIds; ) {
        unchecked {
          reclaimAmount += store
            .tierOfTokenId(address(this), _decodedTokenIds[_i])
            .contributionFloor;

          _i++;
        }
      }

      return (reclaimAmount, _data.memo, delegateAllocations);
    }

    // Return the weighted overflow, and this contract as the delegate so that tokens can be deleted.
    return (
      PRBMath.mulDiv(
        _data.overflow + _amountRedeemed,
        redemptionWeightOf(_decodedTokenIds, _data),
        totalRedemptionWeight(_data)
      ),
      _data.memo,
      delegateAllocations
    );
  }

  /**
    @notice
    Indicates if this contract adheres to the specified interface.

    @dev
    See {IERC165-supportsInterface}.

    @param _interfaceId The ID of the interface to check for adherence to.
  */
  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(JB721Delegate, IERC165) returns (bool) {
    return
      _interfaceId == type(IJBDefifaDelegate).interfaceId || super.supportsInterface(_interfaceId);
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor() {
    codeOrigin = address(this);
  }

  /**
    @param _projectId The ID of the project this contract's functionality applies to.
    @param _directory The directory of terminals and controllers for projects.
    @param _name The name of the token.
    @param _symbol The symbol that the token should be represented by.
    @param _fundingCycleStore A contract storing all funding cycle configurations.
    @param _baseUri A URI to use as a base for full token URIs.
    @param _tokenUriResolver A contract responsible for resolving the token URI for each token ID.
    @param _contractUri A URI where contract metadata can be found. 
    @param _pricing The tier pricing according to which token distribution will be made. Must be passed in order of contribution floor, with implied increasing value.
    @param _store A contract that stores the NFT's data.
    @param _flags A set of flags that help define how this contract works.
  */
  function initialize(
    uint256 _projectId,
    IJBDirectory _directory,
    string memory _name,
    string memory _symbol,
    IJBFundingCycleStore _fundingCycleStore,
    string memory _baseUri,
    IJBTokenUriResolver _tokenUriResolver,
    string memory _contractUri,
    JB721PricingParams memory _pricing,
    IJBTiered721DelegateStore _store,
    JBTiered721Flags memory _flags
  ) public override {
    // Make the original un-initializable.
    if (address(this) == codeOrigin) revert();

    // Stop re-initialization.
    if (address(store) != address(0)) revert();

    // Initialize the superclass.
    JB721Delegate._initialize(_projectId, _directory, _name, _symbol);

    fundingCycleStore = _fundingCycleStore;
    store = _store;
    pricingCurrency = _pricing.currency;

    // Store the base URI if provided.
    if (bytes(_baseUri).length != 0) _store.recordSetBaseUri(_baseUri);

    // Set the contract URI if provided.
    if (bytes(_contractUri).length != 0) _store.recordSetContractUri(_contractUri);

    // Set the token URI resolver if provided.
    if (_tokenUriResolver != IJBTokenUriResolver(address(0)))
      _store.recordSetTokenUriResolver(_tokenUriResolver);

    // Record adding the provided tiers.
    if (_pricing.tiers.length > 0) _store.recordAddTiers(_pricing.tiers);

    // Set the flags if needed.
    if (
      _flags.lockReservedTokenChanges ||
      _flags.lockVotingUnitChanges ||
      _flags.lockManualMintingChanges ||
      _flags.preventOverspending
    ) _store.recordFlags(_flags);

    // Transfer ownership to the initializer.
    _transferOwnership(msg.sender);
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice
    Stores the redemption weights that should be used in the end game phase.

    @dev
    Only the contract's owner can set tier redemption weights.

    @param _tierWeights The tier weights to set.
  */
  function setTierRedemptionWeights(
    DefifaTierRedemptionWeight[] memory _tierWeights
  ) external override onlyOwner {
    // Make sure the game has ended.
    if (fundingCycleStore.currentOf(projectId).number < _END_GAME_PHASE)
      revert GAME_ISNT_OVER_YET();

    // Delete the currently set redemption weights.
    delete _tierRedemptionWeights;

    // Keep a reference to the max tier ID.
    uint256 _maxTierId = store.maxTierIdOf(address(this));

    // Keep a reference to the cumulative amounts.
    uint256 _cumulativeRedemptionWeight;

    // Keep a reference to the number of tier weights.
    uint256 _numberOfTierWeights = _tierWeights.length;

    for (uint256 _i; _i < _numberOfTierWeights; ) {
      // Attempting to set the redemption weight for a tier that does not exist (yet) reverts.
      if (_tierWeights[_i].id > _maxTierId) revert INVALID_TIER_ID();

      // Save the tier weight. Tier's are 1 indexed and should be stored 0 indexed.
      _tierRedemptionWeights[_tierWeights[_i].id - 1] = _tierWeights[_i].redemptionWeight;

      // Increment the cumulative amount.
      _cumulativeRedemptionWeight += _tierWeights[_i].redemptionWeight;

      unchecked {
        ++_i;
      }
    }

    // Make sure the cumulative amount is contained within the total redemption weight.
    if (_cumulativeRedemptionWeight > TOTAL_REDEMPTION_WEIGHT) revert INVALID_REDEMPTION_WEIGHTS();
  }

  /**
    @notice
    Part of IJBRedeemDelegate, this function gets called when the token holder redeems. It will burn the specified NFTs to reclaim from the treasury to the _data.beneficiary.

    @dev
    This function will revert if the contract calling is not one of the project's terminals.

    @param _data The Juicebox standard project redemption data.
  */
  function didRedeem(JBDidRedeemData calldata _data) external payable virtual override {
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      msg.value != 0 ||
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_REDEMPTION_EVENT();

    // If there's nothing being claimed, revert to prevent burning for nothing.
    if (_data.reclaimedAmount.value == 0) revert NOTHING_TO_CLAIM();

    // Check the 4 bytes interfaceId and handle the case where the metadata was not intended for this contract
    // Skip 32 bytes reserved for generic extension parameters.
    if (
      _data.metadata.length < 36 ||
      bytes4(_data.metadata[32:36]) != type(IJB721Delegate).interfaceId
    ) revert INVALID_REDEMPTION_METADATA();

    // Decode the metadata.
    (, , uint256[] memory _decodedTokenIds) = abi.decode(
      _data.metadata,
      (bytes32, bytes4, uint256[])
    );

    // Get a reference to the number of token IDs being checked.
    uint256 _numberOfTokenIds = _decodedTokenIds.length;

    // Keep a reference to the token ID being iterated on.
    uint256 _tokenId;

    // Get a reference to the current funding cycle.
    JBFundingCycle memory _currentFundingCycle = fundingCycleStore.currentOf(projectId);

    // Keep track of whether the redemption is happening during the end phase.
    bool _isEndPhase = _currentFundingCycle.number == _END_GAME_PHASE;

    // Iterate through all tokens, burning them if the owner is correct.
    for (uint256 _i; _i < _numberOfTokenIds; ) {
      // Set the token's ID.
      _tokenId = _decodedTokenIds[_i];

      // Make sure the token's owner is correct.
      if (_owners[_tokenId] != _data.holder) revert UNAUTHORIZED();

      // Burn the token.
      _burn(_tokenId);

      unchecked {
        if (_isEndPhase) ++_redeemedFromTier[store.tierIdOfToken(_tokenId)];
        ++_i;
      }
    }

    // Call the hook.
    _didBurn(_decodedTokenIds);

    // Increment the amount redeemed if this is the end phase.
    if (_isEndPhase) _amountRedeemed += _data.reclaimedAmount.value;
  }

  /** 
    @notice
    Mint reserved tokens within the tier for the provided value.

    @param _mintReservesForTiersData Contains information about how many reserved tokens to mint for each tier.
  */
  function mintReservesFor(
    JBTiered721MintReservesForTiersData[] calldata _mintReservesForTiersData
  ) external override {
    // Keep a reference to the number of tiers there are to mint reserves for.
    uint256 _numberOfTiers = _mintReservesForTiersData.length;

    for (uint256 _i; _i < _numberOfTiers; ) {
      // Get a reference to the data being iterated on.
      JBTiered721MintReservesForTiersData memory _data = _mintReservesForTiersData[_i];

      // Mint for the tier.
      mintReservesFor(_data.tierId, _data.count);

      unchecked {
        ++_i;
      }
    }
  }

  /**
    @notice 
    Delegates votes from the sender to `delegatee`.

    @param _setTierDelegatesData An array of tiers to set delegates for.
   */
  function setTierDelegates(
    JBTiered721SetTierDelegatesData[] memory _setTierDelegatesData
  ) external virtual override {
    // Keep a reference to the number of tier delegates.
    uint256 _numberOfTierDelegates = _setTierDelegatesData.length;

    // Keep a reference to the data being iterated on.
    JBTiered721SetTierDelegatesData memory _data;

    for (uint256 _i; _i < _numberOfTierDelegates; ) {
      // Reference the data being iterated on.
      _data = _setTierDelegatesData[_i];

      // No active delegation to the address 0
      if (_data.delegatee == address(0)) revert DELEGATE_ADDRESS_ZERO();

      _delegateTier(msg.sender, _data.delegatee, _data.tierId);

      unchecked {
        ++_i;
      }
    }
  }

  /**
    @notice 
    Delegates votes from the sender to `delegatee`.

    @param _delegatee The account to delegate tier voting units to.
    @param _tierId The ID of the tier to delegate voting units for.
   */
  function setTierDelegate(address _delegatee, uint256 _tierId) public virtual override {
    _delegateTier(msg.sender, _delegatee, _tierId);
  }

  //*********************************************************************//
  // ----------------------- public transactions ----------------------- //
  //*********************************************************************//

  /** 
    @notice
    Mint reserved tokens within the tier for the provided value.

    @param _tierId The ID of the tier to mint within.
    @param _count The number of reserved tokens to mint. 
  */
  function mintReservesFor(uint256 _tierId, uint256 _count) public override {
    // Get a reference to the project's current funding cycle.
    JBFundingCycle memory _fundingCycle = fundingCycleStore.currentOf(projectId);

    // Minting reserves must not be paused.
    if (
      JBTiered721FundingCycleMetadataResolver.mintingReservesPaused(
        (JBFundingCycleMetadataResolver.metadata(_fundingCycle))
      )
    ) revert RESERVED_TOKEN_MINTING_PAUSED();

    // Keep a reference to the reserved token beneficiary.
    address _reservedTokenBeneficiary = store.reservedTokenBeneficiaryOf(address(this), _tierId);

    // Get a reference to the old delegate.
    address _oldDelegate = _tierDelegation[_reservedTokenBeneficiary][_tierId];

    // Set the delegate as the beneficiary if the beneficiary hasn't already set a delegate.
    if (_oldDelegate == address(0)) {
      _tierDelegation[_reservedTokenBeneficiary][_tierId] = _reservedTokenBeneficiary;
      emit DelegateChanged(_reservedTokenBeneficiary, address(0), _reservedTokenBeneficiary);
    }

    // Record the minted reserves for the tier.
    uint256[] memory _tokenIds = store.recordMintReservesFor(_tierId, _count);

    // Keep a reference to the token ID being iterated on.
    uint256 _tokenId;

    for (uint256 _i; _i < _count; ) {
      // Set the token ID.
      _tokenId = _tokenIds[_i];

      // Mint the token.
      _mint(_reservedTokenBeneficiary, _tokenId);

      emit MintReservedToken(_tokenId, _tierId, _reservedTokenBeneficiary, msg.sender);

      unchecked {
        ++_i;
      }
    }

    // Keep a reference to the tier.
    JB721Tier memory _tier = store.tier(address(this), _tierId);

    // Transfer the voting units to the delegate.
    _transferTierVotingUnits(
      address(0),
      // Use the old delegate if there is one.
      _oldDelegate != address(0) ? _oldDelegate : _reservedTokenBeneficiary,
      _tierId,
      _tier.contributionFloor * _tokenIds.length
    );
  }

  /**
    @notice
    Unusable.
  */
  function setBaseUri(string calldata _baseUri) external pure override {
    _baseUri;
  }

  /**
    @notice
    Unusable.
  */
  function setContractUri(string calldata _contractUri) external pure override {
    _contractUri;
  }

  /**
    @notice
    Unusable.
  */
  function setTokenUriResolver(IJBTokenUriResolver _tokenUriResolver) external pure override {
    _tokenUriResolver;
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  function _processPayment(JBDidPayData calldata _data) internal override {
    // Make sure the game is being played in the correct currency.
    if (_data.amount.currency != pricingCurrency) revert WRONG_CURRENCY();

    // Keep a reference to the address that should be given attestation votes from this mint.
    bytes32 _votingDelegateSegment;

    // Skip the first 32 bytes which are used by the JB protocol to pass the paying project's ID when paying from a JBSplit.
    // The address of the voting delegate for the mint is included in the next 32 bytes reserved for generic extension parameters.
    // Check the 4 bytes interfaceId to verify the metadata is intended for this contract.
    if (
      _data.metadata.length > 68 &&
      bytes4(_data.metadata[64:68]) == type(IDefifaDelegate).interfaceId
    ) {
      // Keep a reference to the the specific tier IDs to mint.
      uint16[] memory _tierIdsToMint;

      // Decode the metadata.
      (, , , _votingDelegateSegment, _tierIdsToMint) = abi.decode(
        _data.metadata,
        (bytes32, bytes32, bytes4, bytes32, uint16[])
      );

      // Make sure something is being minted.
      if (_tierIdsToMint.length == 0) revert NOTHING_TO_MINT();

      // Delegate to the specified address, or to the payer.
      address _votingDelegate = _votingDelegateSegment != bytes32('')
        ? address(uint160(uint256(_votingDelegateSegment)))
        : address(0);

      // Keep a reference to the current tier ID.
      uint256 _currentTierId = _tierIdsToMint[0];

      // Keep a reference to the number of voting units currently accumulated for the given tier.
      uint256 _votingUnitsForCurrentTier;

      // The price of the tier being iterated on.
      uint256 _votingUnits;

      // Keep a reference to the number of tiers.
      uint256 _numberOfTiers = _tierIdsToMint.length;

      // Transfer voting power for each tier.
      for (uint256 _i; _i < _numberOfTiers; ) {
        // Keep track of the current tier being iterated on and its price.
        if (_currentTierId != _tierIdsToMint[_i]) {
          _currentTierId = _tierIdsToMint[_i];
          _votingUnits = store.tier(address(this), _tierIdsToMint[_i]).votingUnits;
        }

        // Get a reference to the old delegate.
        address _oldDelegate = _tierDelegation[_data.payer][_currentTierId];

        // If there's either a new delegate or old delegate, increase the delegate weight.
        if (_votingDelegate != address(0) || _oldDelegate != address(0)) {
          // Increment the total voting units for the tier based on price.
          if (_i < _numberOfTiers - 1 && _tierIdsToMint[_i + 1] == _currentTierId) {
            _votingUnitsForCurrentTier += _votingUnits;
            // Set the tier's total voting power.
          } else {
            // Switch delegates if needed.
            if (_votingDelegate != address(0) && _votingDelegate != _oldDelegate)
              _delegateTier(_data.payer, _votingDelegate, _currentTierId);

            // Transfer the new voting units.
            _transferTierVotingUnits(
              address(0),
              // Delegate to current delegate if a new one isn't specified.
              _votingDelegate != address(0) ? _votingDelegate : _oldDelegate,
              _currentTierId,
              _votingUnitsForCurrentTier + _votingUnits
            );

            // Reset the counter
            _votingUnitsForCurrentTier = 0;
          }
        }

        unchecked {
          ++_i;
        }
      }

      // Mint tiers if they were specified.
      uint256 _leftoverAmount = _mintAll(_data.amount.value, _tierIdsToMint, _data.beneficiary);

      // Make sure the buyer isn't overspending.
      if (_leftoverAmount != 0) revert OVERSPENDING();
    }
  }

  /**
    @notice 
    Gets the amount of voting units an address has for a particular tier.

    @param _account The account to get voting units for.
    @param _tierId The ID of the tier to get voting units for.

    @return The voting units.
  */
  function _getTierVotingUnits(
    address _account,
    uint256 _tierId
  ) internal view virtual returns (uint256) {
    return store.tierVotingUnitsOf(address(this), _account, _tierId);
  }

  /**
    @notice 
    Delegate all of `account`'s voting units for the specified tier to `delegatee`.

    @param _account The account delegating tier voting units.
    @param _delegatee The account to delegate tier voting units to.
    @param _tierId The ID of the tier for which voting units are being transferred.
  */
  function _delegateTier(address _account, address _delegatee, uint256 _tierId) internal virtual {
    // Get the current delegatee
    address _oldDelegate = _tierDelegation[_account][_tierId];

    // Store the new delegatee
    _tierDelegation[_account][_tierId] = _delegatee;

    emit DelegateChanged(_account, _oldDelegate, _delegatee);

    // Move the votes.
    _moveTierDelegateVotes(
      _oldDelegate,
      _delegatee,
      _tierId,
      _getTierVotingUnits(_account, _tierId)
    );
  }

  /**
    @notice 
    Transfers, mints, or burns tier voting units. To register a mint, `from` should be zero. To register a burn, `to` should be zero. Total supply of voting units will be adjusted with mints and burns.

    @param _from The account to transfer tier voting units from.
    @param _to The account to transfer tier voting units to.
    @param _tierId The ID of the tier for which voting units are being transferred.
    @param _amount The amount of voting units to delegate.
   */
  function _transferTierVotingUnits(
    address _from,
    address _to,
    uint256 _tierId,
    uint256 _amount
  ) internal virtual {
    // If minting, add to the total tier checkpoints.
    if (_from == address(0)) _totalTierCheckpoints[_tierId].push(_add, _amount);

    // If burning, subtract from the total tier checkpoints.
    if (_to == address(0)) _totalTierCheckpoints[_tierId].push(_subtract, _amount);

    // Move delegated votes.
    _moveTierDelegateVotes(
      _tierDelegation[_from][_tierId],
      _tierDelegation[_to][_tierId],
      _tierId,
      _amount
    );
  }

  /**
    @notice 
    Moves delegated tier votes from one delegate to another.

    @param _from The account to transfer tier voting units from.
    @param _to The account to transfer tier voting units to.
    @param _tierId The ID of the tier for which voting units are being transferred.
    @param _amount The amount of voting units to delegate.
  */
  function _moveTierDelegateVotes(
    address _from,
    address _to,
    uint256 _tierId,
    uint256 _amount
  ) internal {
    // Nothing to do if moving to the same account, or no amount is being moved.
    if (_from == _to || _amount == 0) return;

    // If not moving from the zero address, update the checkpoints to subtract the amount.
    if (_from != address(0)) {
      (uint256 _oldValue, uint256 _newValue) = _delegateTierCheckpoints[_from][_tierId].push(
        _subtract,
        _amount
      );
      emit TierDelegateVotesChanged(_from, _tierId, _oldValue, _newValue, msg.sender);
    }

    // If not moving to the zero address, update the checkpoints to add the amount.
    if (_to != address(0)) {
      (uint256 _oldValue, uint256 _newValue) = _delegateTierCheckpoints[_to][_tierId].push(
        _add,
        _amount
      );
      emit TierDelegateVotesChanged(_to, _tierId, _oldValue, _newValue, msg.sender);
    }
  }

  /** 
    @notice
    A function that will run when tokens are burned via redemption.

    @param _tokenIds The IDs of the tokens that were burned.
  */
  function _didBurn(uint256[] memory _tokenIds) internal virtual override {
    // Add to burned counter.
    store.recordBurn(_tokenIds);
  }

  /** 
    @notice
    Mints a token in all provided tiers.

    @param _amount The amount to base the mints on. All mints' price floors must fit in this amount.
    @param _mintTierIds An array of tier IDs that are intended to be minted.
    @param _beneficiary The address to mint for.

    @return leftoverAmount The amount leftover after the mint.
  */
  function _mintAll(
    uint256 _amount,
    uint16[] memory _mintTierIds,
    address _beneficiary
  ) internal returns (uint256 leftoverAmount) {
    // Keep a reference to the token ID.
    uint256[] memory _tokenIds;

    // Record the mint. The returned token IDs correspond to the tiers passed in.
    (_tokenIds, leftoverAmount) = store.recordMint(
      _amount,
      _mintTierIds,
      false // Not a manual mint
    );

    // Get a reference to the number of mints.
    uint256 _mintsLength = _tokenIds.length;

    // Keep a reference to the token ID being iterated on.
    uint256 _tokenId;

    // Loop through each token ID and mint.
    for (uint256 _i; _i < _mintsLength; ) {
      // Get a reference to the tier being iterated on.
      _tokenId = _tokenIds[_i];

      // Mint the tokens.
      _mint(_beneficiary, _tokenId);

      emit Mint(_tokenId, _mintTierIds[_i], _beneficiary, _amount, msg.sender);

      unchecked {
        ++_i;
      }
    }
  }

  /**
    @notice
    User the hook to register the first owner if it's not yet registered.

    @param _from The address where the transfer is originating.
    @param _to The address to which the transfer is being made.
    @param _tokenId The ID of the token being transferred.
  */
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal virtual override {
    // Transferred must not be paused when not minting or burning.
    if (_from != address(0)) {
      // Get a reference to the tier.
      JB721Tier memory _tier = store.tierOfTokenId(address(this), _tokenId);

      // Transfers from the tier must be pausable.
      if (_tier.transfersPausable) {
        // Get a reference to the project's current funding cycle.
        JBFundingCycle memory _fundingCycle = fundingCycleStore.currentOf(projectId);

        if (
          _to != address(0) &&
          JBTiered721FundingCycleMetadataResolver.transfersPaused(
            (JBFundingCycleMetadataResolver.metadata(_fundingCycle))
          )
        ) revert TRANSFERS_PAUSED();
      }

      // If there's no stored first owner, and the transfer isn't originating from the zero address as expected for mints, store the first owner.
      if (store.firstOwnerOf(address(this), _tokenId) == address(0))
        store.recordSetFirstOwnerOf(_tokenId, _from);
    }

    super._beforeTokenTransfer(_from, _to, _tokenId);
  }

  /**
    @notice
    Transfer voting units after the transfer of a token.

    @param _from The address where the transfer is originating.
    @param _to The address to which the transfer is being made.
    @param _tokenId The ID of the token being transferred.
   */
  function _afterTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal virtual override {
    // Get a reference to the tier.
    JB721Tier memory _tier = store.tierOfTokenId(address(this), _tokenId);

    // Record the transfer.
    store.recordTransferForTier(_tier.id, _from, _to);

    // Handle any other accounting (ex. account for governance voting units)
    _afterTokenTransferAccounting(_from, _to, _tokenId, _tier);

    super._afterTokenTransfer(_from, _to, _tokenId);
  }

  /**
   @notice
   handles the tier voting accounting

    @param _from The account to transfer voting units from.
    @param _to The account to transfer voting units to.
    @param _tokenId The ID of the token for which voting units are being transferred.
    @param _tier The tier the token ID is part of.
  */
  function _afterTokenTransferAccounting(
    address _from,
    address _to,
    uint256 _tokenId,
    JB721Tier memory _tier
  ) internal virtual {
    _tokenId; // Prevents unused var compiler and natspec complaints.

    // Dont transfer on mint since the delegation will be transferred more efficiently in _processPayment.
    if (_from == address(0)) return;

    // Transfer the voting units.
    _transferTierVotingUnits(_from, _to, _tier.id, _tier.votingUnits);
  }

  // Utils from the Votes extension that is being reused for tier delegation.
  function _add(uint256 a, uint256 b) internal pure returns (uint256) {
    return a + b;
  }

  function _subtract(uint256 a, uint256 b) internal pure returns (uint256) {
    return a - b;
  }
}
