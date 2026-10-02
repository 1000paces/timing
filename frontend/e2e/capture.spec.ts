import { expect, test } from "@playwright/test";

test("a timer records crossings by bib, or with no bib for review", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Timer");
  await page.getByLabel("PIN").fill("1357");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();

  const bib = page.getByLabel("Bib");
  await expect(bib).toBeFocused();
  await bib.fill("101");
  await bib.press("Enter");
  await expect(bib).toHaveValue("");
  await expect(bib).toBeFocused();
  await bib.press("Enter");
  await bib.fill("999");
  await bib.press("Enter");

  const rows = page.getByTestId("capture");
  await expect(rows).toHaveCount(3);
  await expect(rows.nth(0)).toContainText("999");
  await expect(rows.nth(0)).toContainText("unknown bib");
  await expect(rows.nth(1)).toContainText("no bib");
  await expect(rows.nth(2)).toContainText("101");
  await expect(rows.nth(2)).toContainText("Masters 35+ Men");

  // The bib-less crossing waits in the review queue on the Results tab.
  await page.getByRole("tab", { name: "Results" }).click();
  await expect(page.getByTestId("suggestion").filter({ hasText: "has no bib" })).toHaveCount(1);
});
