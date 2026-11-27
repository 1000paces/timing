import { expect, test } from "@playwright/test";

test("a course event shows splits, the Course board, and a missed checkpoint", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Gravel/ }).click();
  await page.getByRole("tab", { name: "Results" }).click();

  const results = page.getByRole("region", { name: "Gravel Open" });
  await expect(results.getByRole("columnheader", { name: "Aid 1" })).toBeVisible();
  await expect(results.getByRole("columnheader", { name: "Aid 2" })).toBeVisible();
  await expect(results.getByRole("columnheader", { name: "Finish", exact: true })).toBeVisible();
  // 702 missed Aid 2: a dash in that cell.
  await expect(results.getByRole("row", { name: /702/ })).toContainText("—");
  await expect(results.getByRole("row", { name: /701/ })).not.toContainText("—");
  // Time is a finisher's; 703 is still out after Aid 1. Columns: Place Bib Name Status Aid1 Aid2 Finish Time Gap.
  await expect(results.getByRole("row", { name: /701/ }).getByRole("cell").nth(7)).toHaveText("55:00.0");
  await expect(results.getByRole("row", { name: /703/ }).getByRole("cell").nth(7)).toHaveText("");

  await page.getByRole("button", { name: "Course" }).click();
  const board = page.getByRole("region", { name: "Gravel Open course" });
  await expect(board.getByTestId("course-point").filter({ hasText: "Aid 1" })).toContainText("3 passed");
  await expect(board.getByTestId("course-point").filter({ hasText: "Aid 2" })).toContainText("1 passed");

  await page.getByRole("tab", { name: /Problems/ }).click();
  await expect(page.getByText("Missed checkpoint").first()).toBeVisible({ timeout: 20_000 });
});

test("a course event's capture screen has no Flag out (and no laps)", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Gravel/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();
  await expect(page.getByTestId("capture").first()).toBeVisible();
  await expect(page.getByRole("button", { name: "Flag out" })).toHaveCount(0);
  await expect(page.getByTestId("capture").filter({ hasText: /Lap \d/ })).toHaveCount(0);
});
