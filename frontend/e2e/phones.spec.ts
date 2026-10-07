import { devices, expect, test } from "@playwright/test";

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

test("a home-screen phone pairs by typing the short code", async ({ page, browser }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();
  await page.getByRole("button", { name: "Pair a phone" }).click();
  const code = (await page.getByTestId("pairing-code").textContent())!;
  expect(code).toMatch(/^[2-9A-HJKMNP-Z]{3}-[2-9A-HJKMNP-Z]{3}$/);

  const phone = await (await browser.newContext({ ...devices["iPhone 13"], baseURL: "http://127.0.0.1:3200" })).newPage();
  await phone.goto("/capture-app/");
  await phone.getByLabel("Pairing code").fill(code.toLowerCase().replace("-", " "));
  await phone.getByLabel("Phone name").fill("Typed phone");
  await phone.getByRole("button", { name: "Pair" }).click();
  await expect(phone.getByRole("button", { name: "Enter" })).toBeVisible();
  await page.getByRole("button", { name: "Done" }).click();
  await expect(page.getByTestId("phone").filter({ hasText: "Typed phone" })).toBeVisible({ timeout: 15_000 });
});
