%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (get_caller_address, get_contract_address, 
                                                get_block_number, get_block_timestamp)
from starkware.cairo.common.math import assert_not_zero, assert_le
from starkware.cairo.common.math_cmp import is_not_zero, is_le
from contracts.token.IERC20 import IERC20
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le
)

struct Timeframe:
    member start_block: felt
    member stop_block: felt
end

struct Stream:
    member sender: felt
    member recipient: felt
    member erc20: felt
    member balance: Uint256
    member withdrawn_balance: Uint256
    member payment_per_block: Uint256
    member timeframe: Timeframe
end

@storage_var
func stream_id() -> (stremId: felt):
end

@storage_var
func streams(id: felt) -> (stream: Stream):
end

# Getters

@view
func get_stream_id{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (id: felt):
    let (id: felt) = stream_id.read()
    return (id)
end

@view
func get_stream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(id: felt) -> (res: Stream):
    let (res: Stream) = streams.read(id)
    return (res)
end

@external
func stream_to{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient: felt,
    erc20: felt,
    initial_balance: Uint256,
    timeframe: Timeframe,
    payment_per_block: Uint256,
    ) -> (id: felt):
    let (id: felt) = stream_id.read()
    let (caller_address) = get_caller_address()

    let stream = Stream(
        sender = caller_address,
        recipient = recipient,
        erc20 = erc20,
        balance = initial_balance,
        withdrawn_balance = Uint256(0, 0),
        payment_per_block = payment_per_block,
        timeframe = timeframe
    )

    let (contract_address) = get_contract_address()
    IERC20.transfer_from(erc20, caller_address, contract_address, initial_balance)

    streams.write(id, stream)
    stream_id.write(id + 1)

    return (id)
end

@external
func refuel{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id: felt,
    amount: Uint256):
    let (stream: Stream) = streams.read(id)
    let (new_balance, overflow: felt) = uint256_add(stream.balance, amount)
    assert_le(overflow, 0)

    let (caller_address) = get_caller_address()
    let (contract_address) = get_contract_address()
    IERC20.transfer_from(stream.erc20, caller_address, contract_address, amount)

    streams.write(id, Stream(
            sender = stream.sender,
            recipient = stream.recipient,
            erc20 = stream.erc20,
            balance = new_balance,
            withdrawn_balance = stream.withdrawn_balance,
            payment_per_block = stream.payment_per_block,
            timeframe = stream.timeframe))
    return ()
end

func get_block_delta{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    timeframe: Timeframe,) -> (delta: felt):
    alloc_locals  # https://starknet.io/docs/how_cairo_works/builtins.html#revoked-implicit-arguments
    
    let (block_number) = get_block_number()

    # block_number <= Timeframe.start_block
    let (res) = is_le(block_number, timeframe.start_block)
    if res == 1:
        return (0)
    end

    # block_number <= Timeframe.stop_block
    let (res) = is_le(block_number, timeframe.stop_block)
    if res == 1:
        return (block_number - timeframe.start_block)
    end
    
    return (timeframe.stop_block - timeframe.start_block)
end