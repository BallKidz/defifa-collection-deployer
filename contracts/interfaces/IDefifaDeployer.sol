// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';
import '@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol';
import '../structs/DefifaLaunchProjectData.sol';
import '../structs/DefifaTimeData.sol';
import './IDefifaGovernor.sol';

interface IDefifaDeployer {
  function SPLIT_DOMAIN() external view returns (uint256);

  function ballkidzProjectId() external view returns (uint256);

  function delegateCodeOrigin() external view returns (address);

  function governorCodeOrigin() external view returns (address);

  function tokenUriResolverCodeOrigin() external view returns (address);

  function controller() external view returns (IJBController3_1);

  function protocolFeeProjectTokenAccount() external view returns (address);

  function delegatesRegistry() external view returns (IJBDelegatesRegistry);

  function timesFor(uint256 _gameId) external view returns (DefifaTimeData memory);

  function mintDurationOf(uint256 _gameId) external view returns (uint256);

  function startOf(uint256 _gameId) external view returns (uint256);

  function refundPeriodDurationOf(uint256 _gameId) external view returns (uint256);

  function endOf(uint256 _gameId) external view returns (uint256);

  function terminalOf(uint256 _gameId) external view returns (IJBPaymentTerminal);

  function distributionLimit(uint256 _gameId) external view returns (uint256);

  function currentGamePhaseOf(uint256 _gameId) external view returns (uint256);

  function nextPhaseNeedsQueueing(uint256 _gameId) external view returns (bool);

  function launchGameWith(
    DefifaLaunchProjectData calldata _launchProjectData
  ) external returns (uint256 projectId, IDefifaGovernor governor);

  function queueNextPhaseOf(uint256 _projectId) external returns (uint256 configuration);

  function claimProtocolProjectToken() external;
}
