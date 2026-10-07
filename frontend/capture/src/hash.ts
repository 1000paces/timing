// The device log checksum, shared with the hub (packs/timing/app/models/device_hash.rb):
// SHA-256 of the entry's canonical JSON — keys sorted, no whitespace, null fields
// omitted — without its own hash. The first entry chains from SHA-256(device id).
export function canonicalJson(entry: Record<string, unknown>): string {
  const keys = Object.keys(entry).filter((k) => k !== "hash" && entry[k] != null).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${JSON.stringify(entry[k])}`).join(",")}}`;
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const digest = (entry: Record<string, unknown>) => sha256Hex(canonicalJson(entry));
export const genesis = (deviceId: string) => sha256Hex(deviceId);

// UUIDv7: 48-bit ms timestamp, then random bits (sortable, like the hub's ids).
export function uuidv7(nowMs = Date.now()): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  for (let i = 0; i < 6; i++) bytes[i] = Math.floor(nowMs / 2 ** (8 * (5 - i))) & 0xff;
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
