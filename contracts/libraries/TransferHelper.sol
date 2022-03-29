// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TransferHelper
 * @dev Wrappers around ERC20 operations that returns the value received by recipent and the actual allowance of approval.
 * To use this library you can add a `using TransferHelper for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
 library TransferHelper{
    function safeTransfer(IERC20 _token, address _to, uint _amount) internal returns (uint amountReceived){
        uint balanceBefore = _token.balanceOf(_to);
        (bool success, ) = address(_token).call(abi.encodeWithSelector(_token.transfer.selector, _to, _amount));
        uint balanceAfter = _token.balanceOf(_to);
        require(success && balanceAfter >= balanceBefore, "TransferHelper:TRANSFER FAILED");
        amountReceived = balanceAfter - balanceBefore;
    }

    function safeTransferFrom(IERC20 _token, address _from, address _to, uint _amount) internal returns (uint amountReceived){
        uint balanceBefore = _token.balanceOf(_to);
        (bool success, ) = address(_token).call(abi.encodeWithSelector(_token.transferFrom.selector, _from, _to, _amount));
        uint balanceAfter = _token.balanceOf(_to);
        require(success && balanceAfter >= balanceBefore, "TransferHelper:TRANSFER FROM FAILED");
        amountReceived = balanceAfter - balanceBefore;
    }

    function safeApprove(IERC20 _token, address _spender, uint256 _amount) internal{
        bool success;
        if (_token.allowance(address(this), _spender) != 0){
            (success, ) = address(_token).call(abi.encodeWithSelector(_token.approve.selector, _spender, 0));
            require(success && _token.allowance(address(this), _spender) == 0, "TransferHelper:APPROVE 0 FAILED");
        }
        (success, ) = address(_token).call(abi.encodeWithSelector(_token.approve.selector, _spender, _amount));
        require(success && _token.allowance(address(this), _spender) == _amount, "TransferHelper:APPROVE FAILED");
    }
}