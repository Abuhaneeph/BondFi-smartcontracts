// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

//NATIVE TOKEN 0xdcc703c0E500B653Ca82273B7BFAd8045D85a470
//PRICE FEED 0x48686EA995462d611F4DA0d65f90B21a30F259A5
//SAVING 0xC0c182d9895882C61C1fC1DF20F858e5E29a4f71
//AFX 0xCcD4D22E24Ab5f9FD441a6E27bC583d241554a3c
//USDT 0x6765e788d5652E22691C6c3385c401a9294B9375
//WETH 0x25a8e2d1e9883D1909040b6B3eF2bb91feAB2e2f
//AFR 0xC7d68ce9A8047D4bF64E6f7B79d388a11944A06E
//cNGN 0x48D2210bd4E72c741F74E6c0E8f356b2C36ebB7A
//cGHS 0x8F11F588B1Cc0Bc88687F7d07d5A529d34e5CD84
//cZAR 0x7dd1aD415F58D91BbF76BcC2640cc6FdD44Aa94b
//cKES 0xaC56E37f70407f279e27cFcf2E31EdCa888EaEe4

contract TestnetToken is ERC20Burnable {
    uint256 private MAX_ALLOCATION = inWei(100);

    // user address => minted amount
    mapping(address => uint256) public allocations;

//    [LINK,  DAI, NEAR , COMP, TRX , AAVE]
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, inWei(1000));
        _mint(address(this), inWei(100000000));
    }

    // faucet minting for testing purposes
    function faucet(uint256 _amount) public {
        uint256 amount = inWei(_amount);
        require(amount > 0, "Amount cannot be zero");
        require(
            allocations[msg.sender] + amount < MAX_ALLOCATION,
            "Cant Mint More Tokens"
        );
        allocations[msg.sender] += amount;
        _approve(address(this), msg.sender, amount);
        transferFrom(address(this), msg.sender, amount);
    }


  function buyToken(uint256 _amount) public {
        uint256 amount = inWei(_amount);
        require(amount > 0, "Amount cannot be zero");
    
        _approve(address(this), msg.sender, amount);
        transferFrom(address(this), msg.sender, amount);
    }

   

function approve(address spender, uint256 amount) public override returns (bool) {
    // Your custom logic here
    return super.approve(spender, amount); // Call the parent contract's approve function
}






    
     function burn(uint256 _amount) public override{
        uint256 balances = balanceOf(msg.sender);
        
        require(_amount > 0);
        require (balances >= _amount); 
        super.burn(_amount);
    }
    
    function getUserTokenAllocation() public view  returns(uint256){
         return allocations[msg.sender];
    }
    
    function inWei(uint256 amount) public view returns (uint256) {
        return amount * 10 ** decimals();
    }

   
}
