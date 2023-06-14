// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JB721TierParams} from "@jbx-protocol/juice-721-delegate/contracts/structs/JB721TierParams.sol";

/// @custom:member token The token being used by the game.
/// @custom:member start The time at which the game should start, measured in seconds.
/// @custom:member mintPeriodDuration The duration of the game's mint phase, measured in seconds.
/// @custom:member mintPeriodDuration The time between the mint phase and the start time when mint's are no longer open but refunds are still allowed, measured in seconds.
struct DefifaOpsData {
    address token;
    uint48 start;
    uint24 mintPeriodDuration;
    uint24 refundPeriodDuration;
}
