import { describe, expect, it } from "vitest";
import { storageWarning } from "./storageHealth";

describe("storageWarning", () => {
  it("blames the certificate only when the page isn't secure or has no offline storage", () => {
    expect(storageWarning({ secure: false, storage: true, persisted: false })).toBe("insecure");
    expect(storageWarning({ secure: true, storage: false, persisted: false })).toBe("insecure");
  });

  it("otherwise suggests installing the app when storage isn't permanent", () => {
    expect(storageWarning({ secure: true, storage: true, persisted: false })).toBe("not-permanent");
    expect(storageWarning({ secure: true, storage: true, persisted: true })).toBeNull();
  });
});
