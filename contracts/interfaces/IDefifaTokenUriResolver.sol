// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/typeface/contracts/interfaces/ITypeface.sol";
import "./IDefifaDelegate.sol";
import "./IDefifaGamePhaseReporter.sol";

interface IDefifaTokenUriResolver {
    function typeface() external view returns (ITypeface);
}
