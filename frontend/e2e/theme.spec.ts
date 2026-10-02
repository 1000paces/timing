import { expect, test } from "@playwright/test";

const bodyBackground = (page: import("@playwright/test").Page) =>
  page.evaluate(() => getComputedStyle(document.body).backgroundColor);

test("console starts in dark mode; the toggle switches to light and is remembered", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("link", { name: /E2E CX/ })).toBeVisible();

  expect(await bodyBackground(page)).toBe("rgb(18, 18, 18)");
  await page.getByRole("button", { name: "Switch to light mode" }).click();
  await expect.poll(() => bodyBackground(page)).toBe("rgb(255, 255, 255)");

  await page.reload();
  await expect(page.getByRole("button", { name: "Switch to dark mode" })).toBeVisible();
  expect(await bodyBackground(page)).toBe("rgb(255, 255, 255)");
});
