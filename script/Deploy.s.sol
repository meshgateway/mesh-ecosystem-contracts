// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";

/// @notice Deploys the MeshSplitterFactory to Robinhood Chain.
/// Usage:
///   forge script script/Deploy.s.sol \
///     --rpc-url $ROBINHOOD_RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --verify \
///     --verifier blockscout \
///     --verifier-url https://robinhoodchain.blockscout.com/api/
contract Deploy is Script {
    // Pons v2 launch locker on Robinhood Chain.
    address constant LOCKER = 0x736D76699C26D0d966744cAe304C000d471f7F35;

    function run() external {
        address treasury = vm.envAddress("MESH_TREASURY");

        vm.startBroadcast();
        MeshSplitterFactory factory = new MeshSplitterFactory(LOCKER, treasury);
        vm.stopBroadcast();

        console.log("MeshSplitterFactory:", address(factory));
        console.log("locker:", factory.locker());
        console.log("treasury:", factory.treasury());
    }
}
