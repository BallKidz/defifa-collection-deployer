// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/typeface/contracts/interfaces/ITypeface.sol";
import "./IDefifaDelegate.sol";
import "./IDefifaGamePhaseReporter.sol";

interface IDefifaTokenUriResolver {
    function codeOrigin() external view returns (address);

    function typeface() external view returns (ITypeface);

    function delegate() external view returns (IDefifaDelegate);

    function initialize(IDefifaDelegate _delegate) external;
}
