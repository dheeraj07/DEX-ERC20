//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "hardhat/console.sol" ;


contract Token{
    string public name;
    string public symbol;
    uint256 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowances;

    event Transfer(address _from, address _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply)
    {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply * (10 ** decimals);
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint value) 
    public 
    returns(bool)
    {
        address from = msg.sender;
        require(balanceOf[from] >= value, "Insufficient balance");
        require(to != address(0),"Cannot burn the tokens");

        transfer(from, to, value);
        return true;
    }

    function transfer(address from, address to, uint value) 
    internal 
    returns(bool)
    {
        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
        return true;
    }


    function approve(address _approver, uint _amount) 
    public 
    returns(bool)
    {
        require(_approver != address(0), "Cannot approve the zero address");
        allowances[msg.sender][_approver] = _amount;
        emit Approval(msg.sender, _approver, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) 
    public 
    returns(bool)
    {
        require(balanceOf[_from] >= _amount, "Insufficient balance");
        require(_to != address(0), "Cannot burn tokens");
        require(_from == msg.sender || allowances[_from][msg.sender] >= _amount, "Insufficient priveleagses");
        if(_from != msg.sender)
        {
            allowances[_from][msg.sender] -= _amount;
        }
        return transfer(_from, _to, _amount);
    }



}