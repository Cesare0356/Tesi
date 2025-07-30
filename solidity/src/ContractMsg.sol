// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "starknet/IStarknetMessaging.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* ---------- Token di sconto -------------------------------------------------- */

contract DiscountToken is ERC20, Ownable{
    constructor() ERC20("Discount", "DSC") Ownable(msg.sender){}

    function mint(address to, uint256 amount) external onlyOwner{
        _mint(to, amount);
    }
    function burnFrom(address account, uint256 amount) public {
        //_spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

}

/* ---------- Gateway L1 <-> L2 ----------------------------------------------- */

contract ContractMsg {
    IStarknetMessaging public immutable _snMessaging;
    DiscountToken    public immutable discountToken;
    address public immutable userAddress;

    constructor(address starknetMessaging_, address useraddress) {
        _snMessaging = IStarknetMessaging(starknetMessaging_);
        userAddress = useraddress;
        discountToken = new DiscountToken();
    }

    function sendMessage(
        uint256 contractAddress,
        uint256 selector,
        uint256[] memory payload
    )
        external
        payable
    {   
        if (discountToken.balanceOf(userAddress) == 1 ether) {
            payload[0] = payload[0] / 2;
            discountToken.burnFrom(userAddress, 1 ether);
        }

        uint256[] memory result = new uint256[](2);
        result[0] = uint256(uint160(userAddress));
        result[1] = payload[0];

        _snMessaging.sendMessageToL2{value: msg.value}(
            contractAddress,
            selector,
            result
        );
    }
    
    function consumeMessageValue(
        uint256 fromAddress,
        uint256[] calldata payload
    ) external {

        _snMessaging.consumeMessageFromL2(
            fromAddress,
            payload
        );

        if (payload.length != 2) {
            revert ("Payload invalido");
        }
        if(payload[1] == 1) {
            discountToken.mint(address(uint160(payload[0])), 1 ether);
        }
    }
}