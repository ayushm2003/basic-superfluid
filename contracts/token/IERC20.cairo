%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IERC20:
    func decimals() -> (decimals: felt):
    end

    func total_supply() -> (totalSupply: Uint256):
    end

    func balance_of(account: felt) -> (balance: Uint256):
    end

    func allowance(owner: felt, spender: felt) -> (remaining: Uint256):
    end

    func transfer(recipient: felt, amount: Uint256) -> ():
    end

    func transfer_from(
            sender: felt, 
            recipient: felt, 
            amount: Uint256
        ) -> ():
    end

    func approve(spender: felt, amount: Uint256) -> ():
    end
end
