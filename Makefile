# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Update dependencies
install          :; forge install
update           :; forge update

# Build
build            :; forge build --sizes
clean            :; forge clean
lint             :; yarn install && yarn run lint

# Testing
test             :; forge test --match-path "src/test/**/*.t.sol" --gas-report
test-contract    :; forge test --match-contract $(contract)
test-fuzz        :; forge test --ffi --match-path "src/test/fuzz/**/*.t.sol"
test-invariant   :; forge test --ffi --match-path "src/test/invariant/**/*.t.sol"
test-integration :; forge test --ffi --match-path "src/test/integration/**/*.t.sol"
test-unit        :; forge test --ffi --match-path "src/test/unit/**/*.t.sol"
