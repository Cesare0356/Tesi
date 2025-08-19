// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../src/ContractMsg.sol";

contract DK is ERC20, Ownable{
    constructor() ERC20("Discount", "DSC") Ownable(msg.sender){}

    function mint(address to, uint256 amount) external onlyOwner{
        _mint(to, amount);
    }
    function burnFrom(address account, uint256 amount) public {
        //_spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

}


/**
 * @notice A simple script to consume a message from Starknet.
 */
contract Value is Script {
    address _publicKey;
    uint256 _privateKey;
    address _contractMsgAddress;
    uint256 _l2Contract;
    uint256 _l2value;
    function setUp() public {
        _privateKey = vm.envUint("ACCOUNT_PRIVATE_KEY");
        _contractMsgAddress = vm.envAddress("CONTRACT_MSG_ADDRESS");
        _l2Contract = vm.envUint("L2_CONTRACT_ADDRESS");
        _publicKey = vm.envAddress("ACCOUNT_ADDRESS");
        _l2value = vm.envUint("L2_VALUE");
    }

    function run() public{
        vm.startBroadcast(_privateKey);

        uint256[] memory payload = new uint256[](2);
        payload[0] = uint256(uint160(_publicKey));
        payload[1] = _l2value;

        ContractMsg(_contractMsgAddress).consumeMessageValue(
            _l2Contract,
            payload);
        vm.stopBroadcast();
    }
}
