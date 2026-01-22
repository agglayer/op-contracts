// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, stdJson, console2 as console } from "forge-std/Script.sol";

import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";
import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";

contract UpgradeOptimismPortal2 is Script {
    using stdJson for string;

    function run() external {
        // owner of ProxyAdmin is needed
        uint256 deployerPrivateKey = vm.promptSecretUint("PRIVATE_KEY");

        string memory input = vm.readFile("scripts/upgrade/input.json");
        string memory chainIdSlug = string(abi.encodePacked('["', vm.toString(block.chainid), '"]'));
        address optimismPortalProxy = input.readAddress(string.concat(chainIdSlug, ".optimismPortalProxy"));
        address proxyAdmin = input.readAddress(string.concat(chainIdSlug, ".proxyAdmin"));

        OptimismPortal2 oldOp2 = OptimismPortal2(payable(optimismPortalProxy));
        uint256 proofMaturityDelaySeconds = oldOp2.proofMaturityDelaySeconds();
        uint256 disputeGameFinalityDelaySeconds = oldOp2.disputeGameFinalityDelaySeconds();

        vm.startBroadcast(deployerPrivateKey);

        // deploy new implementation
        address newImpl = address(new OptimismPortal2(proofMaturityDelaySeconds, disputeGameFinalityDelaySeconds));

        // upgrade proxy
        bytes memory payload = abi.encodeCall(ProxyAdmin.upgrade, (payable(optimismPortalProxy), newImpl));
        console.log("payload to be sent to: ", proxyAdmin);
        console.logBytes(payload);

        // for testing
        // ProxyAdmin(proxyAdmin).upgrade(payable(optimismPortalProxy), newImpl);

        vm.stopBroadcast();
    }
}
