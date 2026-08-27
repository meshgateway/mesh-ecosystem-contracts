// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MeshSplitter} from "../src/MeshSplitter.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";
import {MockERC20, MockFeeEscrow, MockLaunchFactory} from "./mocks/Mocks.sol";

contract MeshSplitterTest is Test {
    MockLaunchFactory ponsFactory;
    MockFeeEscrow escrow;
    MockERC20 usdg;
    MeshSplitterFactory factory;
    MeshSplitter splitter;

    address token = makeAddr("launchedToken");
    address treasury = makeAddr("treasury");
    address payout = makeAddr("payout");
    address deployer = makeAddr("deployer");
    address stranger = makeAddr("stranger");

    function setUp() public {
        ponsFactory = new MockLaunchFactory();
        escrow = new MockFeeEscrow();
        usdg = new MockERC20("USDG", "USDG");
        ponsFactory.register(token, deployer);

        factory = new MeshSplitterFactory(address(ponsFactory), address(escrow), treasury);
        splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // The project links its creator fees to the splitter.
        vm.prank(deployer);
        ponsFactory.transferCreatorFeeRecipient(token, address(splitter));
    }

    function test_factoryWiring() public view {
        assertEq(address(splitter.ponsFactory()), address(ponsFactory));
        assertEq(address(splitter.escrow()), address(escrow));
        assertEq(splitter.treasury(), treasury);
        assertEq(splitter.payout(), payout);
        assertEq(factory.splitterCount(), 1);
        assertEq(factory.splitters(0), address(splitter));
        assertEq(ponsFactory.creatorFeeRecipient(token), address(splitter));
    }

    function test_claimAndRelease_splitsEscrowEth() public {
        escrow.credit{value: 10 ether}(address(splitter));

        vm.prank(stranger); // permissionless
        splitter.claimAndRelease();

        assertEq(treasury.balance, 1 ether);
        assertEq(payout.balance, 9 ether);
        assertEq(address(splitter).balance, 0);
        assertEq(escrow.balanceOf(address(splitter)), 0);
    }

    function test_claimAndRelease_zeroBalanceIsNoop() public {
        splitter.claimAndRelease();
        assertEq(treasury.balance, 0);
        assertEq(payout.balance, 0);
    }

    function test_claimAndRelease_sweepsDirectBalanceToo() public {
        // ETH that arrived outside the escrow path is split as well.
        vm.deal(address(splitter), 2 ether);
        escrow.credit{value: 8 ether}(address(splitter));

        splitter.claimAndRelease();
        assertEq(treasury.balance, 1 ether);
        assertEq(payout.balance, 9 ether);
    }

    function test_claimTokenAndRelease_splitsErc20PairingAsset() public {
        escrow.creditToken(address(splitter), address(usdg), 1_000e18);

        vm.prank(stranger);
        splitter.claimTokenAndRelease(address(usdg));

        assertEq(usdg.balanceOf(treasury), 100e18);
        assertEq(usdg.balanceOf(payout), 900e18);
        assertEq(usdg.balanceOf(address(splitter)), 0);
    }

    function test_release_native() public {
        vm.deal(address(splitter), 10 ether);
        splitter.release(address(0));
        assertEq(treasury.balance, 1 ether);
        assertEq(payout.balance, 9 ether);
    }

    function test_release_roundingFavorsPayout() public {
        usdg.mint(address(splitter), 19);
        splitter.release(address(usdg));
        // 19 * 1000 / 10000 = 1 to treasury, remainder 18 to payout.
        assertEq(usdg.balanceOf(treasury), 1);
        assertEq(usdg.balanceOf(payout), 18);
    }

    function test_transferFeeRecipient_exitHatch() public {
        address newHome = makeAddr("newHome");

        // Only the payout wallet can move the recipiency on.
        vm.prank(stranger);
        vm.expectRevert(MeshSplitter.NotPayout.selector);
        splitter.transferFeeRecipient(token, newHome);

        vm.prank(payout);
        splitter.transferFeeRecipient(token, newHome);
        assertEq(ponsFactory.creatorFeeRecipient(token), newHome);

        // After leaving, the splitter can no longer take the role back.
        vm.prank(payout);
        vm.expectRevert(MockLaunchFactory.NotCreatorFeeRecipient.selector);
        splitter.transferFeeRecipient(token, address(splitter));
    }

    function test_onlyRecipientCanLinkFees() public {
        address other = makeAddr("otherToken");
        ponsFactory.register(other, deployer);

        // The splitter cannot seize recipiency of a token that never
        // linked to it; only the current recipient hands it over.
        vm.prank(payout);
        vm.expectRevert(MockLaunchFactory.NotCreatorFeeRecipient.selector);
        splitter.transferFeeRecipient(other, address(splitter));
    }

    function test_setPayout_onlyCurrentPayout() public {
        vm.expectRevert(MeshSplitter.NotPayout.selector);
        splitter.setPayout(stranger);

        address newPayout = makeAddr("newPayout");
        vm.prank(payout);
        splitter.setPayout(newPayout);
        assertEq(splitter.payout(), newPayout);

        // The old payout wallet loses control after rotation.
        vm.prank(payout);
        vm.expectRevert(MeshSplitter.NotPayout.selector);
        splitter.setPayout(payout);
    }

    function test_setPayout_rejectsZero() public {
        vm.prank(payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        splitter.setPayout(address(0));
    }

    function test_constructor_rejectsZeroAddresses() public {
        address pf = address(ponsFactory);
        address es = address(escrow);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(address(0), es, treasury, payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(pf, address(0), treasury, payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(pf, es, address(0), payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(pf, es, treasury, address(0));
    }

    function testFuzz_claimAndRelease_alwaysSplitsTenPercent(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(address(this), amount);
        escrow.credit{value: amount}(address(splitter));

        splitter.claimAndRelease();

        uint256 expectedTreasury = (uint256(amount) * 1_000) / 10_000;
        assertEq(treasury.balance, expectedTreasury);
        assertEq(payout.balance, uint256(amount) - expectedTreasury);
        assertEq(address(splitter).balance, 0);
    }
}
