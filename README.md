To run tests:

To run fuzz tests:

```
forge test -vvvvv --match-contract Funding
```

Realistic test using on-chain state:

```
forge test -vvvvv --match-contract Realistic --rpc-url $MAINNET_RPC_URL
```

Replace `$MAINNET_RPC_URL` with the URL to your local node, or a node provider endpoint  (Pokt, Infura, Alchemy, etc.).

