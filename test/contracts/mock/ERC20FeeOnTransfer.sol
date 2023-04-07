// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import { ERC20Mock } from "openzeppelin/mocks/ERC20Mock.sol";

contract ERC20FeeOnTransfer is ERC20Mock {
  constructor() ERC20Mock()  {}

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    address spender = _msgSender();
    uint256 fee = amount * 100000000 / 1e9; // 0.1 in 9 decimal places = 10% fee

    amount -= fee;

    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);

    return true;
  }
}
