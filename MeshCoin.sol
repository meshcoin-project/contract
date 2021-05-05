// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts@3.2.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@3.2.0/access/Ownable.sol";


contract MeshCoin is ERC20, Ownable {

    constructor (
            uint256 _totalSupply,
            address _premint,
            address _investor
        ) public ERC20('MeshCoin', 'MSC') {

        capmax =  _totalSupply;                       // MSC totaled 10 billion, 70% of which was mined after the public blockchain went live.
        _mint(_premint, _totalSupply*1/10000);        // 1%% for pool premint
        _mint(_investor, _totalSupply*300/10000);     // 300%% for foundation to vc investor, release weekly
    }

    address public mscpools;
    uint256 public capmax;

    function setpool(address _pool) external onlyOwner {
        require(mscpools == address(0), 'only init once');
        mscpools = _pool;
    }

    function mint(address _to, uint256 _amount) public {
        require(msg.sender == mscpools, 'allow only the pool call');
        require(totalSupply().add(_amount) <= capmax, 'cap exceeded');
        _mint(_to, _amount);
    }

    // If the user transfers TH to contract, it will revert
    receive() external payable {
        revert();
    }
}