// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';

import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol';
import '../DefifaDeployer.sol';
import '../DefifaDelegate.sol';
import '../DefifaGovernor.sol';

// import {CapsulesTypeface} from "../lib/capsules/contracts/CapsulesTypeface.sol";

contract EmptyTest is Test {
  // V3 mainnet controller.
  IJBController controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);

  function testOutput() public {
    // Deploy the codeOrigin for the delegate
    DefifaDelegate _defifaDelegateCodeOrigin = new DefifaDelegate();

    string memory returnedUri = DefifaDelegate(_defifaDelegateCodeOrigin).tokenURI(1000000001);
    string[] memory inputs = new string[](3);
    inputs[0] = 'node';
    inputs[1] = './open.js';
    inputs[2] = returnedUri;
    bytes memory res = vm.ffi(inputs);
    res;
    vm.ffi(inputs);
  }
}
