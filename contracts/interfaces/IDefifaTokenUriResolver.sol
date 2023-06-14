// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITypeface} from "lib/typeface/contracts/interfaces/ITypeface.sol";
import {IDefifaDelegate} from "./IDefifaDelegate.sol";
import {IDefifaGamePhaseReporter} from "./IDefifaGamePhaseReporter.sol";

interface IDefifaTokenUriResolver {
    function typeface() external view returns (ITypeface);
}
