// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'lib/typeface/contracts/interfaces/ITypeface.sol';
import './IDefifaDelegate.sol';
import './IDefifaNoContestReporter.sol';

interface IDefifaTokenUriResolver {
  function codeOrigin() external view returns (address);

  function typeface() external view returns (ITypeface);

  function delegate() external view returns (IDefifaDelegate);

  function tierNameOf(uint256 _tierId) external view returns (string memory);

  function initialize(IDefifaDelegate _delegate, string[] memory _tierNames) external;
}
