// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";

/// @notice Deploys the MeshSplitterFactory to Robinhood Chain.
/// Usage:
///   MESH_TREASURY=0x... forge script script/Deploy.s.sol \
///     --rpc-url $ROBINHOOD_RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --verify \
///     --verifier blockscout \
///     --verifier-url https://robinhoodchain.blockscout.com/api/
contract Deploy is Script {
    // Pons v2 launch factory on Robinhood Chain.
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    // Pons v2 fee escrow on Robinhood Chain.
    address constant ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;

    function run() external {
        address treasury = vm.envAddress("MESH_TREASURY");

        vm.startBroadcast();
        MeshSplitterFactory factory = new MeshSplitterFactory(PONS_FACTORY, ESCROW, treasury);
        vm.stopBroadcast();

        console.log("MeshSplitterFactory:", address(factory));
        console.log("ponsFactory:", factory.ponsFactory());
        console.log("escrow:", factory.escrow());
        console.log("treasury:", factory.treasury());
    }
}
