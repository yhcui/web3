import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

describe("DuggeeToken", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  it("Test init", async function () {
    const DuggeeToken = await viem.deployContract("DuggeeToken", [0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3, 1_000_000 * 10**18]);
  });

});
