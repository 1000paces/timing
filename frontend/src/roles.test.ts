import { describe, expect, it } from "vitest";
import { canAct, isSignedOutError } from "./roles";

describe("canAct", () => {
  it("lets chiefs and admins act, not timers", () => {
    expect(canAct("chief")).toBe(true);
    expect(canAct("admin")).toBe(true);
    expect(canAct("timer")).toBe(false);
  });
});

describe("isSignedOutError", () => {
  it("recognises the API's sign-in errors", () => {
    expect(isSignedOutError(new Error("Sign in required"))).toBe(true);
    expect(isSignedOutError({ message: "Response not successful: Received status code 401" })).toBe(true);
    expect(isSignedOutError(new Error("Not found"))).toBe(false);
    expect(isSignedOutError(undefined)).toBe(false);
  });
});
