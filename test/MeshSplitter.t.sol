// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MeshSplitter} from "../src/MeshSplitter.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";
import {MockERC20, MockLocker} from "./mocks/Mocks.sol";

contract MeshSplitterTest is Test {
    MockLocker locker;
    MockERC20 token;
    MockERC20 weth;
    MeshSplitterFactory factory;
    MeshSplitter splitter;

    address treasury = makeAddr("treasury");
    address payout = makeAddr("payout");
    address deployer = makeAddr("deployer");
    address stranger = makeAddr("stranger");

    function setUp() public {
        locker = new MockLocker();
        token = new MockERC20("Project Token", "PROJ");
        weth = new MockERC20("Wrapped Ether", "WETH");
        locker.register(address(token), deployer, address(weth));

        factory = new MeshSplitterFactory(address(locker), treasury);
        splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // The project links its creator fees to the splitter.
        vm.prank(deployer);
        locker.setFeeRedirect(address(token), address(splitter));
    }

    function test_factoryWiring() public view {
        assertEq(address(splitter.locker()), address(locker));
        assertEq(splitter.treasury(), treasury);
        assertEq(splitter.payout(), payout);
        assertEq(factory.splitterCount(), 1);
        assertEq(factory.splitters(0), address(splitter));
    }

    function test_claimAndRelease_splitsBothAssets() public {
        locker.setPending(address(token), 1_000e18, 5e18);

        vm.prank(stranger); // permissionless
        splitter.claimAndRelease(address(token));

        assertEq(token.balanceOf(treasury), 100e18);
        assertEq(token.balanceOf(payout), 900e18);
        assertEq(weth.balanceOf(treasury), 0.5e18);
        assertEq(weth.balanceOf(payout), 4.5e18);
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(weth.balanceOf(address(splitter)), 0);
    }

    function test_claimAndRelease_revertsWithoutRedirect() public {
        // A second token that never linked its fees to the splitter: the
        // locker must reject the splitter as caller.
        MockERC20 other = new MockERC20("Other", "OTHR");
        locker.register(address(other), deployer, address(weth));
        locker.setPending(address(other), 1e18, 0);

        vm.expectRevert(MockLocker.NotAuthorized.selector);
        splitter.claimAndRelease(address(other));
    }

    function test_release_splitsDirectBalance() public {
        // Fees collected by someone else (Pons automation, the deployer)
        // still land on the splitter; release sweeps them.
        vm.prank(deployer);
        locker.setPending(address(token), 0, 10e18);
        vm.prank(deployer);
        locker.collectFees(address(token));
        assertEq(weth.balanceOf(address(splitter)), 10e18);

        splitter.release(address(weth));
        assertEq(weth.balanceOf(treasury), 1e18);
        assertEq(weth.balanceOf(payout), 9e18);
    }

    function test_release_native() public {
        vm.deal(address(splitter), 10 ether);
        splitter.release(address(0));
        assertEq(treasury.balance, 1 ether);
        assertEq(payout.balance, 9 ether);
    }

    function test_release_zeroBalanceIsNoop() public {
        splitter.release(address(token));
        assertEq(token.balanceOf(treasury), 0);
    }

    function test_release_roundingFavorsPayout() public {
        token.mint(address(splitter), 19);
        splitter.release(address(token));
        // 19 * 1000 / 10000 = 1 to treasury, remainder 18 to payout.
        assertEq(token.balanceOf(treasury), 1);
        assertEq(token.balanceOf(payout), 18);
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
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(address(0), treasury, payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(address(locker), address(0), payout);
        vm.expectRevert(MeshSplitter.ZeroAddress.selector);
        new MeshSplitter(address(locker), treasury, address(0));
    }

    function testFuzz_release_alwaysSplitsTenPercent(uint128 amount) public {
        vm.assume(amount > 0);
        token.mint(address(splitter), amount);
        splitter.release(address(token));

        uint256 expectedTreasury = (uint256(amount) * 1_000) / 10_000;
        assertEq(token.balanceOf(treasury), expectedTreasury);
        assertEq(token.balanceOf(payout), uint256(amount) - expectedTreasury);
        assertEq(token.balanceOf(address(splitter)), 0);
    }
}
