"""superfluid.cairo test file."""
import os
from numpy import rint

import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.testing.contract import StarknetContract
from sympy import Q, sec
from utils.utils import Signer, from_uint, to_uint, uint
from starkware.starknet.public.abi import get_selector_from_name

# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "superfluid.cairo")
ACCOUNT_FILE = os.path.join("contracts", "Account.cairo")
ERC20_FILE = os.path.join("contracts/token", "ERC20.cairo")

sender = Signer(1234322181823212312)
reciever = Signer(1234322181823212313)

@pytest.fixture(scope='module')
def event_loop():
 return asyncio.new_event_loop()

@pytest.fixture(scope="module")
async def contract_factory():
	starknet = await Starknet.empty()

	superfluid = await starknet.deploy(
        source=CONTRACT_FILE
    )
	first_account = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[sender.public_key]
    )
	second_account = await starknet.deploy(
		source=ACCOUNT_FILE,
		constructor_calldata=[reciever.public_key]
	)
	erc20 = await starknet.deploy(
		source=ERC20_FILE,
		constructor_calldata=[first_account.contract_address, first_account.contract_address]
	)

	await sender.send_transaction(account=first_account,
								  to=erc20.contract_address,
	 							  selector_name='mint',
								  calldata=[first_account.contract_address, *to_uint(100**18)])

	# TODO: LOOK INTO EXECUTING TRANSACTION USING ACCOUNT CONTRACT
	# await first_account.__execute__(
	# 	1, (erc20.contract_address, get_selector_from_name('mint'), 0, 2), 2, [first_account.contract_address, to_uint(10**18)], 0 
	# ).invoke()

	# await first_account.__execute__(
	# 	erc20.contract_address,
	# 	get_selector_from_name('mint'),
	# 	[first_account.contract_address, to_uint(10**18), 0]).invoke()
	

	return starknet, superfluid, erc20, first_account, second_account

@pytest.mark.asyncio
async def sanity_check(contract_factory):
	first_account, erc20 = contract_factory
	bal = await erc20.balance_of(first_account.contract_address).call()
	assert from_uint(bal.result.res) == 101**18
	print('SANITY CHECK: ERC20 balance is as expected after minting')

@pytest.mark.asyncio
async def test_stream_to(contract_factory):
	starknet, superfluid, erc20, first_account, second_account = contract_factory

	await sender.send_transaction(account=first_account,
									to=erc20.contract_address,
									selector_name='approve',
									calldata=[superfluid.contract_address, *to_uint(20*10**18)])
	
	allowance = await erc20.allowance(first_account.contract_address, superfluid.contract_address).call()
	assert from_uint(allowance.result.res) == 20*10**18
	print('STREAM TO: ERC20 allowance is as expected')


	id = await sender.send_transaction(account=first_account,
	  								to=superfluid.contract_address,
	   								selector_name='stream_to',
	   								calldata=[
										second_account.contract_address,
	  									erc20.contract_address,
	   									*to_uint(20*10**18),
	   									0, 100,
	   									*to_uint(1*10**18)])
	# print(id.result.response[0])
	stream = await superfluid.get_stream(id.result.response[0]).call()
	# print(stream.result.res[0])

	det = (first_account.contract_address,
				second_account.contract_address,
				erc20.contract_address,
				to_uint(20*10**18),
				to_uint(0),
				to_uint(1*10**18),
				(0, 100))


	assert stream.result.res == det
	print('STREAM TO: Stream details are as expected')


@pytest.mark.asyncio
async def test_fail_stream_to(contract_factory):
	starknet, superfluid, erc20, first_account, second_account = contract_factory

	try:
		await sender.send_transaction(account=first_account,
										to=superfluid.contract_address,
										selector_name='stream_to',
										calldata=[
											second_account.contract_address,
											erc20.contract_address,
											*to_uint(20*10**18),
											0, 100,
											*to_uint(1*10**18)])

		print('STREAM TO FAIL: Stream passed even on no allowance')
	except:
		print('STREAM TO FAIL: Stream failed on no allowance')


@pytest.mark.asyncio
async def test_refuel(contract_factory):
	starknet, superfluid, erc20, first_account, second_account = contract_factory

	await sender.send_transaction(account=first_account,
									to=erc20.contract_address,
									selector_name='approve',
									calldata=[superfluid.contract_address, *to_uint(40*10**18)])
	
	id = await sender.send_transaction(account=first_account,
	  								to=superfluid.contract_address,
	   								selector_name='stream_to',
	   								calldata=[
										second_account.contract_address,
	  									erc20.contract_address,
	   									*to_uint(20*10**18),
	   									0, 100,
	   									*to_uint(1*10**18)])

	await sender.send_transaction(account=first_account,
									to=superfluid.contract_address,
									selector_name='refuel',
									calldata=[id.result.response[0], *to_uint(10*10**18)])
	
	stream = await superfluid.get_stream(id.result.response[0]).call()

	assert stream.result.res[3] == to_uint(30*10**18)
	print('REFUEL: Refueled stream')


@pytest.mark.asyncio
async def test_fail_refuel(contract_factory):
	starknet, superfluid, erc20, first_account, second_account = contract_factory

	await sender.send_transaction(account=first_account,
									to=erc20.contract_address,
									selector_name='approve',
									calldata=[superfluid.contract_address, *to_uint(20*10**18)])

	id = await sender.send_transaction(account=first_account,
	  								to=superfluid.contract_address,
	   								selector_name='stream_to',
	   								calldata=[
										second_account.contract_address,
	  									erc20.contract_address,
	   									*to_uint(20*10**18),
	   									0, 100,
	   									*to_uint(1*10**18)])

	try:
		await sender.send_transaction(account=first_account,
										to=superfluid.contract_address,
										selector_name='refuel',
										calldata=[id.result.response[0], *to_uint(10*10**18)])
	except:
		print('REFUEL FAIL: Refuel failed on not enough allowance')
