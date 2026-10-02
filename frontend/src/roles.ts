export type Role = "timer" | "chief" | "admin";

export function canAct(role: Role): boolean {
  return role === "chief" || role === "admin";
}

export function isSignedOutError(error: unknown): boolean {
  const message = (error as { message?: string } | undefined)?.message ?? "";
  return message.includes("Sign in required") || message.includes("status code 401");
}
