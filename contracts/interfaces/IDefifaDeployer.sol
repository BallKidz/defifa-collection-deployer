// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import "../structs/DefifaLaunchProjectData.sol";
import "../structs/DefifaTimeData.sol";
import "../structs/DefifaDistributionOpsData.sol";
import "./IDefifaDelegate.sol";
import "./IDefifaGovernor.sol";

interface IDefifaDeployer {
    event LaunchGame(
        uint256 indexed gameId,
        IDefifaDelegate indexed delegate,
        IDefifaGovernor indexed governor,
        IJBTokenUriResolver tokenUriResolver,
        address caller
    );

    function SPLIT_DOMAIN() external view returns (uint256);

    function ballkidzProjectId() external view returns (uint256);

    function delegateCodeOrigin() external view returns (address);

    function tokenUriResolverCodeOrigin() external view returns (address);

    function governor() external view returns (IDefifaGovernor);

    function controller() external view returns (IJBController3_1);

    function protocolFeeProjectTokenAccount() external view returns (address);

    function delegatesRegistry() external view returns (IJBDelegatesRegistry);

    function feeDivisor() external view returns (uint256);

    function timesFor(uint256 _gameId) external view returns (DefifaTimeData memory);

    function distributionOpsOf(uint256 _gameId) external view returns (DefifaDistributionOpsData memory);

    function nextPhaseNeedsQueueing(uint256 _gameId) external view returns (bool);

    function launchGameWith(DefifaLaunchProjectData calldata _launchProjectData)
        external
        returns (uint256 gameId);

    function queueNextPhaseOf(uint256 _projectId) external returns (uint256 configuration);

    function claimProtocolProjectToken() external;
}
