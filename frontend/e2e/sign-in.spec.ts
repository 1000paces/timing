import { expect, test, type Page } from "@playwright/test";

async function signIn(page: Page, name: string, pin: string) {
  await page.goto("/console/");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("PIN").fill(pin);
  await page.getByRole("button", { name: "Sign in" }).click();
}

test("wrong PIN shows the API's error", async ({ page }) => {
  await signIn(page, "E2E Chief", "0000");
  await expect(page.getByText("Name or PIN is incorrect")).toBeVisible();
});

test("chief signs in, sees events, signs out", async ({ page }) => {
  await signIn(page, "E2E Chief", "2468");
  await expect(page.getByRole("link", { name: /E2E CX/ })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("link", { name: /E2E CX/ })).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByLabel("PIN")).toBeVisible();
});
