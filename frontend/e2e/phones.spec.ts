import { expect, test } from "@playwright/test";

test("a chief pairs a phone from Capture, sees it listed, and revokes it", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();

  await page.getByRole("button", { name: "Pair a phone" }).click();
  const dialog = page.getByRole("dialog", { name: "Pair a phone" });
  await expect(dialog.getByRole("img", { name: "Pairing QR code" })).toBeVisible();
  const link = await dialog.getByTestId("pairing-link").textContent();
  expect(link).toMatch(/\/capture-app\/\?pair=/);
  await dialog.getByRole("button", { name: "Done" }).click();

  // The phone redeems the code (what the capture app does on opening the link).
  const token = new URL(link!).searchParams.get("pair");
  const paired = await page.request.post("/devices/pair", { data: { token, name: "Test phone" } });
  expect(paired.status()).toBe(201);

  const phones = page.getByTestId("phone");
  await expect(phones.filter({ hasText: "Test phone" })).toBeVisible({ timeout: 15_000 });
  await phones.filter({ hasText: "Test phone" }).getByRole("button", { name: "Revoke Test phone" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Revoke" }).click();
  await expect(phones.filter({ hasText: "Test phone" })).toContainText("Revoked");
});
