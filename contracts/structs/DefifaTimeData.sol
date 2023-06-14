// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { JB721TierParams } from "@jbx-protocol/juice-721-delegate/contracts/structs/JB721TierParams.sol";

/// @custom:member mintDuration The duration of the game's mint phase, measured in seconds.
/// @custom:member refundDuration The time between the mint phase and the start time when mint's are no longer open but refunds are still allowed, measured in seconds.
/// @custom:member start The time at which the game should start, measured in seconds.
struct DefifaTimeData {
    uint48 mintDuration;
    uint48 refundDuration;
    uint48 start;
}
