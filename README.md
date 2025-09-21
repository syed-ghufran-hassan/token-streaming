# STX Streaming Contract

## Overview
This project implements a **Clarity smart contract for token streaming** on the Stacks blockchain.  
It allows one user (the sender) to lock STX into a stream and gradually pay a recipient over a given block timeframe, with an agreed payment per block.  
The contract also supports updates, withdrawals, refunds, and signature-based verification of updates requiring both parties' consent.

## Features
- **Stream Creation**: `stream-to` creates a new stream with recipient, balance, timeframe, and payment per block.  
- **Withdrawals**: Recipients can withdraw tokens that have unlocked by block progression.  
- **Refunds**: Senders can reclaim unused balance if the stream ends early.  
- **Refuel**: Streams can be topped up.  
- **Update Details**: Stream terms (timeframe or payment rate) can be modified with signatures from both sender and recipient.  
- **Signature Verification**: Hashes and signatures are validated on-chain to ensure authenticity.

## Contract Functions
- `stream-to(recipient, initial-balance, timeframe, payment-per-block)` → Creates a new stream.  
- `withdraw(stream-id, amount)` → Withdraw from an active stream.  
- `refund(stream-id)` → Refund the remaining balance to the sender.  
- `refuel(stream-id, amount)` → Add more funds to an existing stream.  
- `update-details(stream-id, new-payment, new-timeframe, sender, sender-signature)` → Modify terms with consent.  
- `hash-stream(stream-id, payment-per-block, timeframe)` → Returns the canonical hash for signing.  
- `validate-signature(hash, signature, signer)` → Verifies signatures against principals.  

## Tests
Written using [Vitest](https://vitest.dev) and Clarinet simnet environment:  
- **Signature verification** ensures off-chain signatures are valid.  
- **Stream updates** confirm that both parties must consent to changes.  
- **Withdrawals and refunds** protect sender and recipient interests.  

Run tests with:
```bash
npm run test
```
