import { describe, it, expect } from "vitest";
import {
  Cl,
  cvToValue,
  signMessageHashRsv,
} from "@stacks/transactions";

// Get accounts from the simnet environment
const accounts = simnet.getAccounts();
const sender = accounts.get("wallet_1")!;   // use this instead of TEST_PRINCIPAL
const recipient = accounts.get("wallet_2")!;
const randomUser = accounts.get("wallet_3")!;

const TEST_PRIVATE_KEY =
  "7287ba251d44a4d3fd9276c88ce34c5c52a038955511cccaf77e61068649c17801";

it("signature verification can be done on stream hashes", () => {
  const hashedStream0 = simnet.callReadOnlyFn(
    "stream",
    "hash-stream",
    [
      Cl.uint(0),
      Cl.uint(0),
      Cl.tuple({ "start-block": Cl.uint(1), "stop-block": Cl.uint(2) }),
    ],
    sender
  );

  const hashBufferCV = hashedStream0.result;
  let messageHash: string = cvToValue(hashBufferCV);
  if (messageHash.startsWith("0x")) {
    messageHash = messageHash.slice(2);
  }

  const signature = signMessageHashRsv({
    messageHash,
    privateKey: TEST_PRIVATE_KEY,
  });

  const verifySignature = simnet.callReadOnlyFn(
    "stream",
    "validate-signature",
    [
      hashBufferCV,
      Cl.bufferFromHex(signature),
      Cl.principal(sender),
    ],
    sender
  );

  expect(cvToValue(verifySignature.result)).toBe(true);
});

it("ensures timeframe and payment per block can be modified with consent of both parties", () => {
  // 1. Create the stream first
  simnet.callPublicFn(
    "stream",
    "stream-to",
    [
      Cl.principal(recipient), // who receives the stream
      Cl.uint(5),              // initial-balance
      Cl.tuple({ "start-block": Cl.uint(0), "stop-block": Cl.uint(3) }),
      Cl.uint(1),              // payment per block
    ],
    sender
  );

  // 2. Hash the stream details you want to update
  const hashedStream0 = simnet.callReadOnlyFn(
    "stream",
    "hash-stream",
    [
      Cl.uint(0), // stream-id (0 because this is the first created stream)
      Cl.uint(1), // new payment per block
      Cl.tuple({ "start-block": Cl.uint(0), "stop-block": Cl.uint(4) }),
    ],
    sender
  );

  const hashBufferCV = hashedStream0.result;
  let messageHash: string = cvToValue(hashBufferCV);
  if (messageHash.startsWith("0x")) {
    messageHash = messageHash.slice(2);
  }

  const senderSignature = signMessageHashRsv({
    messageHash,
    privateKey: TEST_PRIVATE_KEY,
  });

  // 3. Update details with consent
  simnet.callPublicFn(
    "stream",
    "update-details",
    [
      Cl.uint(0), // stream-id
      Cl.uint(1), // new payment per block
      Cl.tuple({ "start-block": Cl.uint(0), "stop-block": Cl.uint(4) }),
      Cl.principal(sender),
      Cl.bufferFromHex(senderSignature),
    ],
    recipient
  );

  // 4. Check the updated state
  const updatedStream = simnet.getMapEntry("stream", "streams", Cl.uint(0));
  expect(updatedStream).toBeSome(
    Cl.tuple({
      sender: Cl.principal(sender),
      recipient: Cl.principal(recipient),
      balance: Cl.uint(5), // same as initial-balance above
      "withdrawn-balance": Cl.uint(0),
      "payment-per-block": Cl.uint(1), // updated value
      timeframe: Cl.tuple({
        "start-block": Cl.uint(0),
        "stop-block": Cl.uint(4), // updated value
      }),
    })
  );
});
