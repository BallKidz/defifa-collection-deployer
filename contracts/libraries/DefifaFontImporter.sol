// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "lib/typeface/contracts/interfaces/ITypeface.sol";

library DefifaFontImporter {
    // @notice Gets the Base64 encoded Capsules-500.otf typeface
    /// @return The Base64 encoded font file
    function getSkinnyFontSource(ITypeface _typeface) internal view returns (bytes memory) {
        return _typeface.sourceOf(Font(300, "normal")); // Capsules font source
    }

    // @notice Gets the Base64 encoded Capsules-500.otf typeface
    /// @return The Base64 encoded font file
    function getBeefyFontSource(ITypeface _typeface) internal view returns (bytes memory) {
        return _typeface.sourceOf(Font(700, "normal")); // Capsules font source
    }
}
