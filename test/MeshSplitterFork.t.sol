// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MeshSplitter} from "../src/MeshSplitter.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";
import {IPonsV2FeeEscrow, IPonsV2LaunchFactory} from "../src/interfaces/IPonsV2.sol";

interface IEscrowCredit {
    function credit(address recipient) external payable;
}

/// @notice Fork tests against the live Pons v2 contracts on Robinhood
/// Chain, using a real launched token (MESH) and its real creator fee
/// recipient. Run with:
///   forge test --match-contract Fork --fork-url https://rpc.mainnet.chain.robinhood.com
/// They are skipped when no fork is active so plain `forge test` stays green.
contract MeshSplitterForkTest is Test {
    // Pons v2 launch factory (verified as PonsV2LaunchFactory).
    address constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    // Pons v2 fee escrow (verified as V2FeeEscrow).
    address constant ESCROW = 0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e;
    // MESH Gateway token, launched on Pons v2, and its creator wallet.
    address constant MESH = 0x14641000A501bdc736116aBf84e6fCeA9B90A713;
    address constant MESH_CREATOR = 0x8DF12b01c9a03C0A76Db42b040f54470Adead3b0;

    address treasury = makeAddr("treasury");
    address payout = makeAddr("payout");

    function _forked() internal view returns (bool) {
        return ESCROW.code.length > 0;
    }

    function test_fork_linkClaimAndSplitAgainstLiveContracts() public {
        if (!_forked()) return;

        MeshSplitterFactory factory = new MeshSplitterFactory(PONS_FACTORY, ESCROW, treasury);
        MeshSplitter splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // The creator links fees to the splitter, exactly as a project
        // would from our dashboard instructions.
        vm.prank(MESH_CREATOR);
        IPonsV2LaunchFactory(PONS_FACTORY).transferCreatorFeeRecipient(MESH, address(splitter));

        // New creator fees now credit to the splitter's escrow balance.
        // The escrow's credit function is public and payable, so fund a
        // deterministic amount instead of waiting for live trades.
        vm.deal(address(this), 10 ether);
        IEscrowCredit(ESCROW).credit{value: 10 ether}(address(splitter));
        assertEq(IPonsV2FeeEscrow(ESCROW).balanceOf(address(splitter)), 10 ether);

        // Anyone can trigger the claim and split.
        vm.prank(makeAddr("stranger"));
        splitter.claimAndRelease();

        assertEq(treasury.balance, 1 ether);
        assertEq(payout.balance, 9 ether);
        assertEq(address(splitter).balance, 0);
        assertEq(IPonsV2FeeEscrow(ESCROW).balanceOf(address(splitter)), 0);
    }

    function test_fork_exitHatchReturnsRecipiency() public {
        if (!_forked()) return;

        MeshSplitterFactory factory = new MeshSplitterFactory(PONS_FACTORY, ESCROW, treasury);
        MeshSplitter splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        vm.prank(MESH_CREATOR);
        IPonsV2LaunchFactory(PONS_FACTORY).transferCreatorFeeRecipient(MESH, address(splitter));

        // The project leaves: the payout wallet hands recipiency back to
        // the creator without MeshGateway's involvement.
        vm.prank(payout);
        splitter.transferFeeRecipient(MESH, MESH_CREATOR);

        // The splitter no longer holds the role, so it cannot take it back.
        vm.prank(payout);
        vm.expectRevert();
        splitter.transferFeeRecipient(MESH, address(splitter));
    }

    function test_fork_strangerCannotSeizeRecipiency() public {
        if (!_forked()) return;

        MeshSplitterFactory factory = new MeshSplitterFactory(PONS_FACTORY, ESCROW, treasury);
        MeshSplitter splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // Without the creator's transfer, the splitter has no claim on the
        // token's fees and the factory rejects the attempt.
        vm.prank(payout);
        vm.expectRevert();
        splitter.transferFeeRecipient(MESH, address(splitter));
    }
}
