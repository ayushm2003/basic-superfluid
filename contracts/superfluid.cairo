%lang starknet
%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.token.IERC20 import IERC20
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub,
)

struct Timeframe:
    member startBlock: Uint256
    member stopBlock: Uint256
end

struct Stream:
    member sender: felt
    member recipient: felt
    member erc20: felt
    member balance: Uint256
    member withdrawnBalance: Uint256
    member paymentPerBlock: Uint256
    member timeframe: Timeframe
end

