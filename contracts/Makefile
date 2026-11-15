# Second Wind — contract tasks
# Reads the repo-root .env when present, so `make deploy-base` needs no shell exports.

SHELL := /bin/bash
ENV_FILE ?= ../.env

ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

.PHONY: build test test-fork deploy-base deploy-unichain deploy-reactive seed crash1 crash2 fmt

build:
	forge build

test:
	forge test -vv

test-fork:
	forge test --match-path 'test/fork/*' --fork-url $(BASE_SEPOLIA_RPC) -vv

deploy-base:
	forge script script/DeployBase.s.sol --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

deploy-unichain:
	forge script script/DeployUnichain.s.sol --rpc-url $(UNICHAIN_SEPOLIA_RPC) --broadcast

deploy-reactive:
	forge script script/DeployReactive.s.sol --rpc-url $(LASNA_RPC) --broadcast --value 0.5ether

seed:
	forge script script/SeedMarket.s.sol --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

crash1:
	forge script script/Crash.s.sol --rpc-url $(BASE_SEPOLIA_RPC) --broadcast --private-key $(LIQUIDATOR_KEY)

crash2:
	forge script script/Crash.s.sol:Crash2 --rpc-url $(BASE_SEPOLIA_RPC) --broadcast --private-key $(LIQUIDATOR_KEY)

fmt:
	forge fmt
