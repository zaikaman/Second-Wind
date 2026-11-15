# Second Wind — contract tasks
# Reads the repo-root .env when present, so `make deploy-base` needs no shell exports.

SHELL := /bin/bash
ENV_FILE ?= ../.env

ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

.PHONY: build test test-fork deploy-base deploy-reactive deploy-pool deploy-unichain wire wire-registry seed crash1 crash2 fmt

build:
	forge build

test:
	forge test -vv

test-fork:
	forge test --match-path 'test/fork/*' --fork-url $(BASE_SEPOLIA_RPC) -vv

# Each script file holds more than one contract, so the contract must be named explicitly.
deploy-base:
	forge script script/DeployBase.s.sol:DeployBase --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

deploy-reactive:
	forge script script/DeployReactive.s.sol:DeployReactive --rpc-url $(LASNA_RPC) --broadcast

deploy-pool:
	forge script script/DeployBase.s.sol:DeployPool --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

deploy-unichain:
	forge script script/DeployUnichain.s.sol:DeployUnichain --rpc-url $(UNICHAIN_SEPOLIA_RPC) --broadcast

wire:
	forge script script/Wire.s.sol:Wire --rpc-url $(LASNA_RPC) --broadcast

wire-registry:
	forge script script/Wire.s.sol:WireRegistry --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

seed:
	forge script script/SeedMarket.s.sol --rpc-url $(BASE_SEPOLIA_RPC) --broadcast

crash1:
	forge script script/Crash.s.sol --rpc-url $(BASE_SEPOLIA_RPC) --broadcast --private-key $(LIQUIDATOR_KEY)

crash2:
	forge script script/Crash.s.sol:Crash2 --rpc-url $(BASE_SEPOLIA_RPC) --broadcast --private-key $(LIQUIDATOR_KEY)

fmt:
	forge fmt
