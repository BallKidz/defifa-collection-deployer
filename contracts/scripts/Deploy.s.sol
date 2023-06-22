// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import "../DefifaDeployer.sol";
import "../DefifaGovernor.sol";
import "../DefifaTokenUriResolver.sol";
import "forge-std/Script.sol";

contract DeployMainnet is Script {
    // V3_1 mainnet controller.
    IJBController3_1 _controller = IJBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b);

    address _defifaBallkidz = 0x11834239698c7336EF232C00a2A9926d3375DF9D;
    IJBDelegatesRegistry _delegateRegistry = IJBDelegatesRegistry(0x7A53cAA1dC4d752CAD283d039501c0Ee45719FaC);
    ITypeface _typeface = ITypeface(0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A);

    uint256 _defifaProjectId = 369;

    IERC20 _defifaToken = IERC20(address(_controller.tokenStore().tokenOf(_defifaProjectId)));
    IERC20 _jbxToken = IERC20(address(_controller.tokenStore().tokenOf(_defifaProjectId)));

    uint256 _blockTime = 12;

    function run() external {
        vm.startBroadcast();

        // Deploy the codeOrigin for the delegate.
        DefifaDelegate _defifaDelegateCodeOrigin = new DefifaDelegate(_defifaToken, _jbxToken);

        // Deploy the token uri resolver.
        DefifaTokenUriResolver _defifaTokenUriResolver = new DefifaTokenUriResolver(_typeface);

        // Deploy the governor.
        DefifaGovernor _defifaGovernor = new DefifaGovernor(_controller, _blockTime);

        // Deploy the deployer.
        DefifaDeployer _defifaDeployer = new DefifaDeployer(
          address(_defifaDelegateCodeOrigin),
          _defifaTokenUriResolver,
          _defifaGovernor,
          _controller,
          _delegateRegistry,
          _defifaBallkidz,
          _defifaProjectId,
          _defifaBallkidz
        );

        _defifaGovernor.transferOwnership(address(_defifaDeployer));
        console.log(address(_defifaDeployer));
    }
}

contract DeployGoerli is Script {
    // V3_1 goerli controller.
    IJBController3_1 _controller = IJBController3_1(0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6);

    address _defifaBallkidz = 0x11834239698c7336EF232C00a2A9926d3375DF9D;
    IJBDelegatesRegistry _delegateRegistry = IJBDelegatesRegistry(0xCe3Ebe8A7339D1f7703bAF363d26cD2b15D23C23);
    ITypeface _typeface = ITypeface(0x8Df17136B20DA6D1E23dB2DCdA8D20Aa4ebDcda7);

    uint256 _defifaProjectId = 1;

    IERC20 _defifaToken = IERC20(address(_controller.tokenStore().tokenOf(_defifaProjectId)));
    IERC20 _jbxToken = IERC20(address(_controller.tokenStore().tokenOf(_defifaProjectId)));

    uint256 _blockTime = 12;

    function run() external {
        vm.startBroadcast();

        // Deploy the codeOrigin for the delegate
        DefifaDelegate _defifaDelegateCodeOrigin = new DefifaDelegate(_defifaToken, _jbxToken);

        // Deploy the token uri resolver.
        DefifaTokenUriResolver _defifaTokenUriResolver = new DefifaTokenUriResolver(_typeface);

        // Deploy the governor.
        DefifaGovernor _defifaGovernor = new DefifaGovernor(_controller, _blockTime);

        // Deploy the deployer.
        DefifaDeployer _defifaDeployer = new DefifaDeployer(
          address(_defifaDelegateCodeOrigin),
          _defifaTokenUriResolver,
          _defifaGovernor,
          _controller,
          _delegateRegistry,
          _defifaBallkidz,
          _defifaProjectId,
          _defifaBallkidz
        );

        _defifaGovernor.transferOwnership(address(_defifaDeployer));

        console.log(address(_defifaDeployer));
    }
}
