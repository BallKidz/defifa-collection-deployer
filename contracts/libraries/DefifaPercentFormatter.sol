// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts/utils/Strings.sol';

library DefifaPercentFormatter {
  using Strings for uint256;

  /**
    @notice
    A string representation of the percent of the given value to the total redemption weight.

    @param _value The value to convert into a percentage of the total redemption weight.

    @return The formatted percent string.
  */
  function getFormattedPercentageOfRedemptionWeight(
    uint256 _value,
    uint256 _total,
    uint256 _decimalFidelity
  ) internal pure returns (string memory) {
    uint256 quotient = (_value * _total * (10 ^ _decimalFidelity)) / _total; // Multiply to the order of _IMG_DECIMAL_FIDELITY for extra decimal place precision)
    uint256 integerPart = quotient / 10000; // Extract the integer part
    uint256 decimalPart = quotient % 10000; // Extract the decimal part

    // Concatenate the integer and decimal parts with a decimal point
    return
      string(
        abi.encodePacked(
          integerPart.toString(),
          '.',
          _formatDecimalPart(decimalPart, _decimalFidelity),
          '%'
        )
      );
  }

  /**
    @notice
    A formatted decimal component to a number.

    @param _value The decimal value to format.

    @return strValue The formatted string.
  */
  function _formatDecimalPart(
    uint256 _value,
    uint256 _decimalFidelity
  ) private pure returns (string memory strValue) {
    strValue = _value.toString();
    // Add leading zeros if necessary
    for (uint256 i = bytes(strValue).length; i < _decimalFidelity; i++)
      strValue = string(abi.encodePacked('0', strValue));
  }
}
