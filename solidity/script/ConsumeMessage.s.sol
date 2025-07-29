// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../src/ContractMsg.sol";

/**
 * @notice A simple script to consume a message from Starknet.
 */
contract Value is Script {
    uint256 _publicKey;
    uint256 _privateKey;
    address _contractMsgAddress;
    uint256 _l2Contract;

    function setUp() public {
        _privateKey = vm.envUint("ACCOUNT_PRIVATE_KEY");
        _contractMsgAddress = vm.envAddress("CONTRACT_MSG_ADDRESS");
        _l2Contract = vm.envUint("L2_CONTRACT_ADDRESS");
    }

    function run() public{
        vm.startBroadcast(_privateKey);

        // This value must match what was sent from starknet.
        // In our example, we have sent the value 1 with starkli.
        uint256[] memory payload = new uint256[](2);
        payload[0] = uint256(uint160(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266));
        payload[1] = 1;

        // The address must be the contract's address that has sent the message.
        ContractMsg(_contractMsgAddress).consumeMessageValue(
            0x039b409cb0299bb6f13a714a553ed733373fd36607d979bade367fb45aeab968,
            payload);

        vm.stopBroadcast();
    }
}
