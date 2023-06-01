// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import "../DefifaDelegate.sol";
import "../DefifaTokenUriResolver.sol";
import "../interfaces/IDefifaGamePhaseReporter.sol";

// import {CapsulesTypeface} from "../lib/capsules/contracts/CapsulesTypeface.sol";

contract GamePhaseReporter is IDefifaGamePhaseReporter {
    function currentGamePhaseOf(uint256 _gameId) external pure returns (DefifaGamePhase) {
        _gameId;
        return DefifaGamePhase.COUNTDOWN;
    }
}

contract GamePotReporter is IDefifaGamePotReporter {
    function gamePotOf(uint256 _gameId) external pure returns (uint256, address, uint256) {
        _gameId;
        return (696900000000000000, JBTokens.ETH, 18);
    }
}

contract SVGTest is Test {
    IJBController _controller;
    IJBDirectory _directory;
    IJBFundingCycleStore _fundingCycleStore;
    IJBTiered721DelegateStore _store;
    ITypeface _typeface;

    address defifaBallkidz = address(0);
    address delegateRegistry = address(0);

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth");
        _controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);
        _directory = IJBDirectory(0x65572FB928b46f9aDB7cfe5A4c41226F636161ea);
        _fundingCycleStore = IJBFundingCycleStore(0x6f18cF9173136c0B5A6eBF45f19D58d3ff2E17e6);
        _store = IJBTiered721DelegateStore(0x67C31B9557201A341312CF78d315542b5AD83074);
        _typeface = ITypeface(0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A);
    }

    function testWithTierImage() public {
        DefifaDelegate _delegate = DefifaDelegate(Clones.clone(address(new DefifaDelegate())));
        DefifaTokenUriResolver _resolver =
            DefifaTokenUriResolver(Clones.clone(address(new DefifaTokenUriResolver(_typeface))));
        GamePhaseReporter _gamePhaseReporter = new GamePhaseReporter();
        GamePotReporter _gamePotReporter = new GamePotReporter();

        JB721TierParams[] memory _tiers = new JB721TierParams[](1);
        _tiers[0] = JB721TierParams({
            price: 1e18,
            initialQuantity: 100,
            votingUnits: 1,
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIPFSUri: bytes32(0xfb17901b2b08444d2bbe92ca39bdd64eab27b0481e841fcd9f14aeb56e28513b),
            category: 0,
            allowManualMint: false,
            shouldUseReservedTokenBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: true
        });
        _delegate.initialize({
            _gameId: 12345,
            _directory: _directory,
            _name: "Example collection",
            _symbol: "EX",
            _fundingCycleStore: _fundingCycleStore,
            _baseUri: "",
            _tokenUriResolver: _resolver,
            _contractUri: "",
            _tiers: _tiers,
            _currency: 1,
            _store: _store,
            _flags: JBTiered721Flags({
                lockReservedTokenChanges: false,
                lockVotingUnitChanges: false,
                lockManualMintingChanges: false,
                preventOverspending: false
            }),
            _gamePhaseReporter: _gamePhaseReporter,
            _gamePotReporter: _gamePotReporter,
            _defaultVotingDelegate: address(0)
        });

        string[] memory _tierNames = new string[](1);
        _tierNames[0] = "lakers win. no one scores over 40pts.";

        _resolver.initialize(_delegate, _tierNames);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./open.js";
        inputs[2] = _resolver.getUri(1000000001);
        bytes memory res = vm.ffi(inputs);
        res;
        vm.ffi(inputs);
    }

    event K(bytes4 k);

    function testWithOutTierImage() public {
        DefifaDelegate _delegate = DefifaDelegate(Clones.clone(address(new DefifaDelegate())));
        DefifaTokenUriResolver _resolver =
            DefifaTokenUriResolver(Clones.clone(address(new DefifaTokenUriResolver(_typeface))));
        GamePhaseReporter _gamePhaseReporter = new GamePhaseReporter();
        GamePotReporter _gamePotReporter = new GamePotReporter();

        JB721TierParams[] memory _tiers = new JB721TierParams[](1);
        _tiers[0] = JB721TierParams({
            price: 1e18,
            initialQuantity: 100,
            votingUnits: 0,
            reservedRate: 0,
            reservedTokenBeneficiary: address(0),
            encodedIPFSUri: bytes32(""),
            category: 0,
            allowManualMint: false,
            shouldUseReservedTokenBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: true
        });
        _delegate.initialize({
            _gameId: 123,
            _directory: _directory,
            _name: "Example collection: Who will win the 2023-2024 premier league?",
            _symbol: "DEFIFA: EXAMPLE",
            _fundingCycleStore: _fundingCycleStore,
            _baseUri: "",
            _tokenUriResolver: _resolver,
            _contractUri: "",
            _tiers: _tiers,
            _currency: 1,
            _store: _store,
            _flags: JBTiered721Flags({
                lockReservedTokenChanges: false,
                lockVotingUnitChanges: false,
                lockManualMintingChanges: false,
                preventOverspending: false
            }),
            _gamePhaseReporter: _gamePhaseReporter,
            _gamePotReporter: _gamePotReporter,
            _defaultVotingDelegate: address(0)
        });

        string[] memory _tierNames = new string[](1);
        _tierNames[0] = "liverpool wins by 10 points";

        _resolver.initialize(_delegate, _tierNames);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./open.js";
        inputs[2] = _resolver.getUri(1000000000);
        bytes memory res = vm.ffi(inputs);
        res;
        vm.ffi(inputs);

        emit K(type(IDefifaDelegate).interfaceId);
    }
}
