// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';

import '@openzeppelin/contracts/proxy/Clones.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol';
import '../DefifaDelegate.sol';
import '../DefifaHTMLTokenUriResolver.sol';

// import {CapsulesTypeface} from "../lib/capsules/contracts/CapsulesTypeface.sol";

contract EmptyTest is Test {
  IJBController _controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);
  IJBDirectory _directory = IJBDirectory(0x65572FB928b46f9aDB7cfe5A4c41226F636161ea);
  IJBFundingCycleStore _fundingCycleStore =
    IJBFundingCycleStore(0x6f18cF9173136c0B5A6eBF45f19D58d3ff2E17e6);
  IJBTiered721DelegateStore _store =
    IJBTiered721DelegateStore(0x167ea060D75727Aa93C1c02873f189d22ef98856);

  address defifaBallkidz = address(0);
  address delegateRegistry = address(0);
      
  function testOutput() public {
    DefifaDelegate _delegate = DefifaDelegate(Clones.clone(address(new DefifaDelegate())));
    DefifaHTMLTokenUriResolver _resolver = DefifaHTMLTokenUriResolver(
      Clones.clone(address(new DefifaHTMLTokenUriResolver()))
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
      // encodedIPFSUri: encodeIPFS('QmSX1ktBWiTX1BJs8hDEVN93vRVJq6iNrpR36ByjRXfLra'),
      encodedIPFSUri: bytes32(0xc425bad3a9a07b60af6037e9ee61a7a67f07f8781611cef220923264ca75d609),
      // returns QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51 but should be QmZJUHkLG2dqc4yKBAxk3YwUyiCAP3s4phphoT7wtppe6V
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
      _baseUri: 'ipfs://',
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
    _tierNames[0] = 'Cleveland';

    _resolver.initialize(_delegate, _tierNames);

    string[] memory inputs = new string[](3);
    inputs[0] = 'node';
    inputs[1] = './openHTML.js';
    inputs[2] = _resolver.getUri(1000000001);
    bytes memory res = vm.ffi(inputs);
    res;
    vm.ffi(inputs);
  }
}