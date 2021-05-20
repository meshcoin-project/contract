// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts@3.2.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@3.2.0/access/Ownable.sol";


contract Meshcoin is ERC20, Ownable {

    using SafeMath for uint256;

    constructor (
            uint256 _totalSupply,
            address _premint,
            address _investor
        ) public ERC20('Meshcoin', 'MSC') {

        require(_premint != address(0), "_premint address cannot be 0");
        require(_investor != address(0), "_investor address cannot be 0");

        capmax =  _totalSupply;                                      // MSC totaled 10 billion, 70% of which was mined after the public blockchain went live.
        uint256 _premintNum = _totalSupply.mul(20).div(100).div(10000);
        _mint(_premint, _premintNum);                                // 20%%% for pool premint
        _mint(_investor, _totalSupply.mul(3).div(100));              // 3% for foundation to vc investor, release weekly

        liquidityMintTotal = _premintNum;
        liquidityMintLimit = capmax.mul(27).div(100);                // Total liquidity mining + companion mining is 27%
        publicChainExchangeTotal = 0;                                // Total number of public chain coins already exchanged
        publicChainExchangeLimit = capmax.mul(70).div(100);          // Public chain coins can only be exchanged for up to 70% of the token
    }

    address public mscpools;
    uint256 public capmax;
    uint256 public liquidityMintTotal;
    uint256 public liquidityMintLimit;
    uint256 public publicChainExchangeTotal;
    uint256 public publicChainExchangeLimit;

    function setpool(address _pool) external onlyOwner {
        require(_pool != address(0), "_pool address cannot be 0");
        require(mscpools == address(0), 'only init once');
        mscpools = _pool;
    }

    //Liquidity Mining Additions
    function liquidityMiningMint(address _to, uint256 _amount) external {
        require(_to != address(0), "_to address cannot be 0");
        require(msg.sender == mscpools, 'allow only the pool call');
        require(liquidityMintTotal.add(_amount) <= liquidityMintLimit, 'cap exceeded');
        liquidityMintTotal = liquidityMintTotal.add(_amount);
        _mint(_to, _amount);
    }

    //The chain bridge between the public chain and ERC20 uses this function
    function chainBridgeMint(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "_to address cannot be 0");
        require(publicChainExchangeTotal.add(_amount) <= publicChainExchangeLimit, 'cap exceeded');
        publicChainExchangeTotal = publicChainExchangeTotal.add(_amount);
        _mint(_to, _amount);
    }
    
    //The chain bridge between the public chain and ERC20 uses this function
    function chainBridgeMintBurn(uint256 _amount) external onlyOwner {
        publicChainExchangeTotal = publicChainExchangeTotal.sub(_amount);
        _burn(msg.sender, _amount);
    }

    // If the user transfers TH to contract, it will revert
    receive() external payable {
        revert();
    }
}