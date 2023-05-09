// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';

import '@openzeppelin/contracts/proxy/Clones.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol';
import '../DefifaDelegate.sol';
import '../DefifaTokenUriResolver.sol';

// import {CapsulesTypeface} from "../lib/capsules/contracts/CapsulesTypeface.sol";

contract EmptyTest is Test {
  IJBController _controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);
  IJBDirectory _directory = IJBDirectory(0x65572FB928b46f9aDB7cfe5A4c41226F636161ea);
  IJBFundingCycleStore _fundingCycleStore =
    IJBFundingCycleStore(0x6f18cF9173136c0B5A6eBF45f19D58d3ff2E17e6);
  IJBTiered721DelegateStore _store =
    IJBTiered721DelegateStore(0x167ea060D75727Aa93C1c02873f189d22ef98856);
  ITypeface _typeface = ITypeface(0x8Df17136B20DA6D1E23dB2DCdA8D20Aa4ebDcda7);

  address defifaBallkidz = address(0);
  address delegateRegistry = address(0);

  function testWithTierImage() public {
    DefifaDelegate _delegate = DefifaDelegate(Clones.clone(address(new DefifaDelegate())));
    DefifaTokenUriResolver _resolver = DefifaTokenUriResolver(
      Clones.clone(address(new DefifaTokenUriResolver(_typeface)))
    );

    JB721TierParams[] memory _tiers = new JB721TierParams[](1);
    _tiers[0] = JB721TierParams({
      contributionFloor: 1E18,
      lockedUntil: 0,
      initialQuantity: 100,
      votingUnits: 0,
      reservedRate: 0,
      reservedTokenBeneficiary: address(0),
      royaltyRate: 0,
      royaltyBeneficiary: address(0),
      encodedIPFSUri: bytes32(0xfb17901b2b08444d2bbe92ca39bdd64eab27b0481e841fcd9f14aeb56e28513b),
      category: 1,
      allowManualMint: false,
      shouldUseReservedTokenBeneficiaryAsDefault: false,
      shouldUseRoyaltyBeneficiaryAsDefault: false,
      transfersPausable: false
    });
    _delegate.initialize({
      _projectId: 123,
      _directory: _directory,
      _name: 'Example collection',
      _symbol: 'EX',
      _fundingCycleStore: _fundingCycleStore,
      _baseUri: '',
      _tokenUriResolver: _resolver,
      _contractUri: '',
      _pricing: JB721PricingParams({
        tiers: _tiers,
        currency: 1,
        decimals: 18,
        prices: IJBPrices(address(0))
      }),
      _store: _store,
      _flags: JBTiered721Flags({
        lockReservedTokenChanges: false,
        lockVotingUnitChanges: false,
        lockManualMintingChanges: false,
        preventOverspending: false
      })
    });

    string[] memory _tierNames = new string[](1);
    _tierNames[0] = 'liverpool';

    _resolver.initialize(_delegate, _tierNames);

    string[] memory inputs = new string[](3);
    inputs[0] = 'node';
    inputs[1] = './open.js';
    inputs[2] = _resolver.getUri(1000000001);
    bytes memory res = vm.ffi(inputs);
    res;
    vm.ffi(inputs);
  }

  function testWithOutTierImage() public {
    DefifaDelegate _delegate = DefifaDelegate(Clones.clone(address(new DefifaDelegate())));
    DefifaTokenUriResolver _resolver = DefifaTokenUriResolver(
      Clones.clone(address(new DefifaTokenUriResolver(_typeface)))
    );

    JB721TierParams[] memory _tiers = new JB721TierParams[](1);
    _tiers[0] = JB721TierParams({
      contributionFloor: 1E18,
      lockedUntil: 0,
      initialQuantity: 100,
      votingUnits: 0,
      reservedRate: 0,
      reservedTokenBeneficiary: address(0),
      royaltyRate: 0,
      royaltyBeneficiary: address(0),
      encodedIPFSUri: bytes32(''),
      category: 1,
      allowManualMint: false,
      shouldUseReservedTokenBeneficiaryAsDefault: false,
      shouldUseRoyaltyBeneficiaryAsDefault: false,
      transfersPausable: false
    });
    _delegate.initialize({
      _projectId: 123,
      _directory: _directory,
      _name: 'Example collection',
      _symbol: 'EX',
      _fundingCycleStore: _fundingCycleStore,
      _baseUri: '',
      _tokenUriResolver: _resolver,
      _contractUri: '',
      _pricing: JB721PricingParams({
        tiers: _tiers,
        currency: 1,
        decimals: 18,
        prices: IJBPrices(address(0))
      }),
      _store: _store,
      _flags: JBTiered721Flags({
        lockReservedTokenChanges: false,
        lockVotingUnitChanges: false,
        lockManualMintingChanges: false,
        preventOverspending: false
      })
    });

    string[] memory _tierNames = new string[](1);
    _tierNames[0] = 'liverpool';

    _resolver.initialize(_delegate, _tierNames);

    string[] memory inputs = new string[](3);
    inputs[0] = 'node';
    inputs[1] = './open.js';
    inputs[2] = _resolver.getUri(1000000001);
    bytes memory res = vm.ffi(inputs);
    res;
    vm.ffi(inputs);
  }
}
