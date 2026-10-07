export type StorageHealth = { secure: boolean; storage: boolean; persisted: boolean; offlineApp?: boolean };

// Which warning (if any) the phone should show about keeping its crossings:
// "insecure" — the page isn't a secure context or has no offline storage, so the
//   hub certificate isn't trusted (or the browser is too old);
// "not-permanent" — storage works, but the browser hasn't promised to keep it
//   (browsers grant that to installed / home-screen apps).
export function storageWarning(h: StorageHealth): "insecure" | "not-permanent" | null {
  if (!h.secure || !h.storage) return "insecure";
  return h.persisted ? null : "not-permanent";
}

export async function checkStorage(): Promise<StorageHealth> {
  const secure = window.isSecureContext;
  const storage = typeof indexedDB !== "undefined" && "storage" in navigator;
  let persisted = false;
  try {
    persisted = (await navigator.storage?.persisted?.()) || (await navigator.storage?.persist?.()) || false;
  } catch {
    persisted = false;
  }
  return { secure, storage, persisted, offlineApp: !!navigator.serviceWorker?.controller };
}
