%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (get_caller_address, get_contract_address, 
                                                get_block_number, get_block_timestamp)
from starkware.cairo.common.math import assert_not_zero, assert_le
from starkware.cairo.common.math_cmp import is_not_zero, is_le
from contracts.token.IERC20 import IERC20
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_mul, uint256_le
)
from starkware.cairo.common.keccak import unsafe_keccak

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

struct Signature:
    member v: felt
    member r: felt
    member s: felt
end

@storage_var
func stream_id() -> (stremId: felt):
end

@storage_var
func streams(id: felt) -> (stream: Stream):
end

@storage_var
func domain_separator() -> (separator: felt):
end

@storage_var
func UPDATE_DETAILS_HASH() -> (hash: felt):
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

@view
func get_domain_separator{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res: felt):
    let (res: felt) = domain_separator.read()
    return (res)
end

@view
func get_update_details_hash{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res: felt):
    let (res: felt) = UPDATE_DETAILS_HASH.read()
    return (res)
end

@constructor
func constructor{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
        let (contract_address) = get_contract_address()
        # let domain = unsafe_keccak([contract_address], 1)
        # domain_separator.write(domain)
        return ()
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

# for recipient
@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id: felt):
    alloc_locals
    let (stream: Stream) = streams.read(id)

    let (caller_address) = get_caller_address()
    assert stream.recipient = caller_address

    let (balance) = get_balance(id, caller_address)

    let (new_withdrawn_balance, overflow: felt) = uint256_add(stream.withdrawn_balance, balance)
    assert_le(overflow, 0)

    # update withdrawn_balance
    streams.write(id, Stream(
            sender = stream.sender,
            recipient = stream.recipient,
            erc20 = stream.erc20,
            balance = stream.balance,
            withdrawn_balance = new_withdrawn_balance,
            payment_per_block = stream.payment_per_block,
            timeframe = stream.timeframe))
    
    # transfer to recipient
    IERC20.transfer(stream.erc20, caller_address, balance)
    return ()
end

# For sender after stream ends
@external
func refund{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id: felt):
    alloc_locals
    let (stream: Stream) = streams.read(id)

    # Unathorised
    let (caller_address) = get_caller_address()
    assert stream.sender = caller_address

    # Stream still active
    let (block_number) = get_block_number()
    assert_le(stream.timeframe.stop_block, block_number+1)

    let (balance) = get_balance(id, caller_address)
    # update balance
    let (new_balance) = uint256_sub(stream.balance, balance)
    streams.write(id, Stream(
            sender = stream.sender,
            recipient = stream.recipient,
            erc20 = stream.erc20,
            balance = new_balance,
            withdrawn_balance = stream.withdrawn_balance,
            payment_per_block = stream.payment_per_block,
            timeframe = stream.timeframe))
    
    # transfer extra to sender
    IERC20.transfer(stream.erc20, caller_address, balance)
    return ()
end

func get_balance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id: felt,
    who: felt) -> (balance: Uint256):
    alloc_locals
    let (stream: Stream) = streams.read(id)
    
    let (block_delta) = get_block_delta(stream.timeframe)
    let (recipient_balance, carry) = uint256_mul(Uint256(block_delta, 0), stream.payment_per_block)
    assert carry = Uint256(0, 0)

    if who == stream.recipient:
        let (balance) = uint256_sub(recipient_balance, stream.withdrawn_balance)
        return (balance)
    end
    if who == stream.sender:
        let (balance) = uint256_sub(stream.balance, recipient_balance)
        return (balance)
    end

    return (Uint256(0, 0))
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

# WIP
@external
func update_details{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id: felt,
    payment_per_block: Uint256,
    timeframe: Timeframe,
    signature: Signature):
    let (stream: Stream) = streams.read(id)
    return ()
end
