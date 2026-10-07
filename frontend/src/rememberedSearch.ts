// Filters live in the page address; this also remembers them per screen and
// event in this browser, so leaving a tab and coming back keeps them.
export type KeyValueStore = { getItem(key: string): string | null; setItem(key: string, value: string): void; removeItem(key: string): void };

function browserStore(): KeyValueStore | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    return null;
  }
}

const KEY = (screen: string) => `timing:filters:${screen}`;

// The address's own filters win; otherwise the last ones remembered here.
export function initialSearch(screen: string, search: string, store: KeyValueStore | null = browserStore()): string {
  if (search) return search;
  try {
    return store?.getItem(KEY(screen)) ?? "";
  } catch {
    return "";
  }
}

export function rememberSearch(screen: string, search: string, store: KeyValueStore | null = browserStore()): void {
  try {
    if (search) store?.setItem(KEY(screen), search);
    else store?.removeItem(KEY(screen));
  } catch {
    // Storage blocked (private mode etc.): filters still work, just aren't remembered.
  }
}

// Puts the filters in the address (replacing, so Back isn't flooded) and remembers them.
export function showSearch(screen: string, search: string): void {
  window.history.replaceState(window.history.state, "", `${window.location.pathname}${search}`);
  rememberSearch(screen, search);
}
