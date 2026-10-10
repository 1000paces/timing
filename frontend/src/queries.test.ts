import { describe, expect, it } from "vitest";
import { print } from "graphql";
import { INSERT_CROSSING } from "./queries";

describe("INSERT_CROSSING", () => {
  it("declares checkpointId and forwards it to insertCrossing", () => {
    const text = print(INSERT_CROSSING);
    expect(text).toContain("$checkpointId: ID");
    expect(text).toContain("checkpointId: $checkpointId");
  });
});
