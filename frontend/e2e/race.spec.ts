import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "../..");

function simulateRace(): string {
  return execFileSync("bin/rails", ["runner", "frontend/e2e/simulate.rb"], {
    cwd: repoRoot,
    env: { ...process.env, RAILS_ENV: "test", TIMING_DB: "sqlite3", TIMING_SQLITE_PATH: "storage/e2e.sqlite3" },
    encoding: "utf8",
  });
}

test("chief runs a simulated race and clears the review queue", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E CX/ }).click();

  await page.getByLabel("Laps").fill("3");
  await page.getByRole("button", { name: "Set laps" }).click();
  await expect(page.getByText("3 laps").first()).toBeVisible();

  // Review Focus 1: a double-click must record one start.
  await page.getByRole("button", { name: "GO" }).dblclick();
  await expect(page.getByText(/Started at/)).toBeVisible();
  await expect(page.getByRole("button", { name: "GO" })).toHaveCount(0);

  const output = simulateRace();
  expect(output).toContain("GO rulings: 1");

  const missed = page.getByTestId("suggestion").filter({ hasText: "missed crossing" });
  await expect(missed.first()).toBeVisible({ timeout: 20_000 });
  for (let remaining = await missed.count(); remaining > 0; remaining--) {
    await missed.first().getByRole("button", { name: "Accept" }).click();
    await expect(missed).toHaveCount(remaining - 1, { timeout: 20_000 });
  }

  await expect(page.getByTestId("suggestion")).toHaveCount(0, { timeout: 20_000 });
  const statuses = page.getByTestId("rider-status");
  await expect(statuses).toHaveCount(12);
  await expect(statuses.filter({ hasNotText: "finished" })).toHaveCount(0);
});
