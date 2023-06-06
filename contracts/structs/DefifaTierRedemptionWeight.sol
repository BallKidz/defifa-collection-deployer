// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @member id The tier's ID.
/// @member redemptionWeight the weight that all tokens of this tier can be redeemed for.
struct DefifaTierRedemptionWeight {
    uint256 id;
    uint256 redemptionWeight;
}
