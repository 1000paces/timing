import type { Role } from "./roles";

export type Official = { id: string; name: string; role: Role };

async function body(res: Response): Promise<Record<string, unknown>> {
  try {
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export async function currentOfficial(): Promise<Official | null> {
  const res = await fetch("/session", { credentials: "same-origin" });
  return res.ok ? ((await res.json()) as Official) : null;
}

export async function signIn(name: string, pin: string): Promise<Official> {
  const res = await fetch("/session", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, pin }),
  });
  const data = await body(res);
  if (!res.ok) throw new Error(typeof data.error === "string" ? data.error : `Sign-in failed (${res.status})`);
  return data as unknown as Official;
}

export async function signOut(): Promise<void> {
  await fetch("/session", { method: "DELETE", credentials: "same-origin" });
}
