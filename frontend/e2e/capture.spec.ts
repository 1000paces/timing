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
  await bib.fill("101");
  await bib.press("Enter");
  await bib.fill("201");
  await bib.press("Enter");

  // Masters 35+ Men started 10 minutes ago with 60 s laps (seed), and 101 already
  // has 2 laps; Masters 50+ Men hasn't started, so bib 201 has no lap.
  const rows = page.getByTestId("capture");
  await expect(rows).toHaveCount(5);
  await expect(rows.nth(0)).toContainText("201");
  await expect(rows.nth(0)).not.toContainText("Lap");
  await expect(rows.nth(1)).toContainText("101");
  await expect(rows.nth(1)).toContainText("Lap 4");
  await expect(rows.nth(1).getByTestId("lap-warning")).toContainText("Short lap");
  await expect(rows.nth(2)).toContainText("999");
  await expect(rows.nth(2)).toContainText("unknown bib");
  await expect(rows.nth(3)).toContainText("no bib");
  await expect(rows.nth(4)).toContainText("101");
  await expect(rows.nth(4)).toContainText("Masters 35+ Men");
  await expect(rows.nth(4)).toContainText("Lap 3");
  await expect(rows.nth(4).getByTestId("lap-warning")).toContainText("Long lap");
  await expect(rows.nth(4).getByTestId("lap-warning")).toContainText("typical 1:00.0");

  // Deleting the earlier 101 crossing (after a confirm) renumbers the later one.
  await rows.nth(4).getByRole("button", { name: "Delete capture" }).click();
  const confirm = page.getByRole("dialog");
  await expect(confirm).toContainText("Delete bib 101 at");
  await confirm.getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(4);
  await expect(rows.nth(1)).toContainText("Lap 3");

  // The bib-less crossing waits in the review queue on the Results tab.
  await page.getByRole("tab", { name: "Results" }).click();
  const queue = page.getByTestId("suggestion");
  await expect(queue.filter({ hasText: /^No bib · \d\d:\d\d:\d\d · \+\d+:\d\d\.\d/ })).toHaveCount(1);
  await expect(queue.filter({ hasText: "Unknown rider: bib 999 · " })).toHaveCount(1);
});
