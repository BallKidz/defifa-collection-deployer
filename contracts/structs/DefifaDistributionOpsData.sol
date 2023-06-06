// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";

/// @member terminal The payment terminal where funds are being accepted through.
/// @member token The token the game is played with.
/// @member distributionLimit The amount that is permitted to be distributed from the terminal.
struct DefifaDistributionOpsData {
    IJBPaymentTerminal terminal;
    address token;
    uint88 distributionLimit;
}
