// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TucuToken} from "../src/TucuToken.sol";
import {TucuProxy} from "../src/TucuProxy.sol";

contract TucuTokenTest is Test {
    TucuToken internal token;
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        TucuToken implementation = new TucuToken();
        TucuProxy proxy = new TucuProxy(address(implementation), admin);
        token = TucuToken(address(proxy));
    }

    function testInitializationAndRoles() public view {
        assertEq(token.name(), "Tucu");
        assertEq(token.symbol(), "TUCU");
        assertEq(token.totalSupply(), 0);
        assertEq(token.maxSupply(), 100_000_000 ether);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin));
    }

    function testMintBurnAndSupplyLimit() public {
        vm.prank(admin);
        token.mint(user, 25 ether);
        assertEq(token.balanceOf(user), 25 ether);

        vm.prank(user);
        token.burn(5 ether);
        assertEq(token.balanceOf(user), 20 ether);
        assertEq(token.totalSupply(), 20 ether);

        vm.prank(admin);
        token.setMaxSupply(20 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                TucuToken.MaxSupplyExceeded.selector,
                20 ether + 1,
                20 ether
            )
        );
        vm.prank(admin);
        token.mint(user, 1);
    }

    function testCannotSetMaximumBelowCurrentSupply() public {
        vm.prank(admin);
        token.mint(user, 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                TucuToken.MaxSupplyBelowCurrentSupply.selector,
                1 ether,
                2 ether
            )
        );
        vm.prank(admin);
        token.setMaxSupply(1 ether);
    }

    function testPauseBlocksTransfersAndMinting() public {
        vm.prank(admin);
        token.mint(user, 2 ether);
        vm.prank(admin);
        token.pause();

        vm.expectRevert();
        vm.prank(user);
        token.transfer(outsider, 1 ether);
        vm.expectRevert();
        vm.prank(admin);
        token.mint(user, 1 ether);

        vm.prank(admin);
        token.unpause();
        vm.prank(user);
        token.transfer(outsider, 1 ether);
        assertEq(token.balanceOf(outsider), 1 ether);
    }

    function testUnauthorizedAccountsCannotAdministerToken() public {
        vm.expectRevert();
        vm.prank(outsider);
        token.mint(outsider, 1 ether);
        vm.expectRevert();
        vm.prank(outsider);
        token.pause();
        vm.expectRevert();
        vm.prank(outsider);
        token.setMaxSupply(1 ether);
    }

    function testProxyCannotBeInitializedTwice() public {
        vm.expectRevert();
        token.initialize(outsider);
    }

    function testImplementationCannotBeInitializedDirectly() public {
        TucuToken implementation = new TucuToken();
        vm.expectRevert();
        implementation.initialize(admin);
    }
}
