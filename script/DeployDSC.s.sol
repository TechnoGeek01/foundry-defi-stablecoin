// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public pricefeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();

        (
            address wethUsdPriceFeed,
            address wbtcUsdPricefeed,
            address weth,
            address wbtc,
            uint deployerkey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPricefeed];

        vm.startBroadcast(deployerkey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        dsc.transferOwnership(engine)
        vm.stopBroadcast();
        return (dsc,engine)
    }
}
