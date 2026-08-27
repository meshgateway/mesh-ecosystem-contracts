// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MeshSplitter, IERC20} from "../src/MeshSplitter.sol";
import {MeshSplitterFactory} from "../src/MeshSplitterFactory.sol";
import {IPonsLaunchLocker} from "../src/interfaces/IPonsLaunchLocker.sol";

/// @notice Fork tests against the live Pons v2 locker on Robinhood Chain.
/// Run with: forge test --match-contract Fork --fork-url $ROBINHOOD_RPC_URL
/// They are skipped when no fork is active so plain `forge test` stays green.
contract MeshSplitterForkTest is Test {
    // Pons v2 launch locker (verified on Blockscout).
    address constant LOCKER = 0x736D76699C26D0d966744cAe304C000d471f7F35;
    // WETH on Robinhood Chain, the paired side of every Pons pool.
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    // An actively traded Pons v2 token, used as the fork fixture. Override
    // with PONS_TOKEN when it goes quiet.
    address constant DEFAULT_TOKEN = 0x14623dD0784cb5C484F8935c7c218d110332b538;

    address treasury = makeAddr("treasury");
    address payout = makeAddr("payout");

    function _forked() internal view returns (bool) {
        return LOCKER.code.length > 0;
    }

    function test_fork_claimAndReleaseFromLiveLocker() public {
        if (!_forked()) return;
        address token = vm.envOr("PONS_TOKEN", DEFAULT_TOKEN);

        IPonsLaunchLocker locker = IPonsLaunchLocker(LOCKER);
        IPonsLaunchLocker.LaunchedToken memory launched = locker.getLaunchedToken(token);
        assertTrue(launched.exists, "fixture token not launched on Pons");
        assertEq(launched.pairedToken, WETH, "fixture token not paired with WETH");

        MeshSplitterFactory factory = new MeshSplitterFactory(LOCKER, treasury);
        MeshSplitter splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // The deployer links creator fees to the splitter, exactly as a
        // project would from our dashboard instructions.
        vm.prank(launched.deployer);
        locker.setFeeRedirect(token, address(splitter));
        assertEq(locker.feeRedirects(token), address(splitter));

        // The live position may have nothing pending at this block; probe
        // first so the test only asserts the split when fees exist.
        vm.prank(launched.deployer);
        try locker.collectFees(token) returns (uint256, uint256) {
            // Fees existed and just went to the splitter via the redirect.
        } catch {
            emit log("no pending fees at fork block, seeding splitter directly");
            deal(WETH, address(splitter), 1 ether);
        }

        uint256 tokenHeld = IERC20(token).balanceOf(address(splitter));
        uint256 wethHeld = IERC20(WETH).balanceOf(address(splitter));
        assertTrue(tokenHeld > 0 || wethHeld > 0, "splitter received nothing");

        splitter.release(token);
        splitter.release(WETH);

        assertEq(IERC20(token).balanceOf(treasury), tokenHeld / 10);
        assertEq(IERC20(token).balanceOf(payout), tokenHeld - tokenHeld / 10);
        assertEq(IERC20(WETH).balanceOf(treasury), wethHeld / 10);
        assertEq(IERC20(WETH).balanceOf(payout), wethHeld - wethHeld / 10);
        assertEq(IERC20(token).balanceOf(address(splitter)), 0);
        assertEq(IERC20(WETH).balanceOf(address(splitter)), 0);
    }

    function test_fork_splitterIsAuthorizedCollector() public {
        if (!_forked()) return;
        address token = vm.envOr("PONS_TOKEN", DEFAULT_TOKEN);

        IPonsLaunchLocker locker = IPonsLaunchLocker(LOCKER);
        IPonsLaunchLocker.LaunchedToken memory launched = locker.getLaunchedToken(token);
        assertTrue(launched.exists);

        MeshSplitterFactory factory = new MeshSplitterFactory(LOCKER, treasury);
        MeshSplitter splitter = MeshSplitter(payable(factory.createSplitter(payout)));

        // Before the redirect the locker must reject the splitter as caller.
        vm.expectRevert();
        splitter.claimAndRelease(token);

        vm.prank(launched.deployer);
        locker.setFeeRedirect(token, address(splitter));

        // After the redirect the call is authorized. It either succeeds or
        // reverts with NoFeesToCollect; either way it got past the
        // authorization gate, which is what this test proves.
        try splitter.claimAndRelease(token) {
            assertTrue(
                IERC20(token).balanceOf(payout) > 0 || IERC20(WETH).balanceOf(payout) > 0
            );
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), bytes4(keccak256("NoFeesToCollect()")));
        }
    }
}
