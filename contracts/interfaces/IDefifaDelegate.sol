// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPrices.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721Delegate.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol';
import '@jbx-protocol/juice-721-delegate/contracts/structs/JB721TierParams.sol';
import '@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721SetTierDelegatesData.sol';
import '@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721MintReservesForTiersData.sol';
import '@jbx-protocol/juice-721-delegate/contracts/structs/JBTiered721MintForTiersData.sol';
import '@jbx-protocol/juice-721-delegate/contracts/structs/JB721PricingParams.sol';
import './../structs/DefifaTierRedemptionWeight.sol';
import './IDefifaGamePhaseReporter.sol';

interface IDefifaDelegate is IJB721Delegate {
  event Mint(
    uint256 indexed tokenId,
    uint256 indexed tierId,
    address indexed beneficiary,
    uint256 totalAmountContributed,
    address caller
  );

  event MintReservedToken(
    uint256 indexed tokenId,
    uint256 indexed tierId,
    address indexed beneficiary,
    address caller
  );

  event TierDelegateVotesChanged(
    address indexed delegate,
    uint256 indexed tierId,
    uint256 previousBalance,
    uint256 newBalance,
    address caller
  );

  event DelegateChanged(
    address indexed delegator,
    address indexed fromDelegate,
    address indexed toDelegate
  );

  function TOTAL_REDEMPTION_WEIGHT() external view returns (uint256);

  function name() external view returns (string memory);

  function redemptionWeightOf(uint256 _tokenId) external view returns (uint256);

  function tierRedemptionWeights() external view returns (uint256[128] memory);

  function codeOrigin() external view returns (address);

  function redemptionWeightIsSet() external view returns (bool);

  function store() external view returns (IJBTiered721DelegateStore);

  function fundingCycleStore() external view returns (IJBFundingCycleStore);

  function gamePhaseReporter() external view returns (IDefifaGamePhaseReporter);

  function pricingCurrency() external view returns (uint256);

  function firstOwnerOf(uint256 _tokenId) external view returns (address);

  function baseURI() external view returns (string memory);

  function contractURI() external view returns (string memory);

  function getTierDelegate(address _account, uint256 _tier) external view returns (address);

  function getTierVotes(address _account, uint256 _tier) external view returns (uint256);

  function getPastTierVotes(
    address _account,
    uint256 _tier,
    uint256 _blockNumber
  ) external view returns (uint256);

  function getTierTotalVotes(uint256 _tier) external view returns (uint256);

  function getPastTierTotalVotes(
    uint256 _tier,
    uint256 _blockNumber
  ) external view returns (uint256);

  function setTierDelegate(address _delegatee, uint256 _tierId) external;

  function setTierDelegates(
    JBTiered721SetTierDelegatesData[] memory _setTierDelegatesData
  ) external;

  function setTierRedemptionWeights(DefifaTierRedemptionWeight[] memory _tierWeights) external;

  function mintReservesFor(
    JBTiered721MintReservesForTiersData[] memory _mintReservesForTiersData
  ) external;

  function mintReservesFor(uint256 _tierId, uint256 _count) external;

  function initialize(
    uint256 _gameId,
    IJBDirectory _directory,
    string memory _name,
    string memory _symbol,
    IJBFundingCycleStore _fundingCycleStore,
    string memory _baseUri,
    IJBTokenUriResolver _tokenUriResolver,
    string memory _contractUri,
    JB721TierParams[] memory _tiers,
    uint48 _currency,
    IJBTiered721DelegateStore _store,
    JBTiered721Flags memory _flags,
    IDefifaGamePhaseReporter _gamePhaseReporter
  ) external;
}
