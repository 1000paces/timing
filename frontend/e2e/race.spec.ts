import { expect, test, type Page } from "@playwright/test";
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

async function openEvent(page: Page, name: string, pin: string) {
  await page.goto("/console/");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("PIN").fill(pin);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E CX/ }).click();
}

test("chief runs a simulated race and clears the review queue", async ({ page, browser }) => {
  // Review Focus 3: a timer, watching alongside, never gets action buttons.
  const timerContext = await browser.newContext();
  const timer = await timerContext.newPage();
  await openEvent(timer, "E2E Timer", "1357");
  await expect(timer.getByText("Not started", { exact: true })).toBeVisible();
  await expect(timer.getByRole("button", { name: "GO" })).toHaveCount(0);
  await expect(timer.getByRole("button", { name: "Set laps" })).toHaveCount(0);

  await openEvent(page, "E2E Chief", "2468");

  await page.getByLabel("Laps").fill("3");
  await page.getByRole("button", { name: "Set laps" }).click();
  await expect(page.getByText("3 laps").first()).toBeVisible();

  // Review Focus 1: a double-click must record one start.
  await page.getByRole("button", { name: "GO" }).dblclick();
  await expect(page.getByText(/Started at/)).toBeVisible();
  await expect(page.getByRole("button", { name: "GO" })).toHaveCount(0);

  // Coming back while standings can't load (hub busy) must not offer GO again.
  await page.getByRole("link", { name: "Events" }).click();
  await page.route("**/graphql", (route) =>
    (route.request().postData() ?? "").includes("query Standings") ? route.abort() : route.continue(),
  );
  await page.getByRole("link", { name: /E2E CX/ }).click();
  await expect(page.getByText(/Started at/)).toBeVisible();
  await expect(page.getByRole("button", { name: "GO" })).toHaveCount(0);
  await page.unroute("**/graphql");

  const output = simulateRace();
  expect(output).toContain("GO rulings: 1");

  const missed = page.getByTestId("suggestion").filter({ hasText: "missed crossing" });
  await expect(missed.first()).toBeVisible({ timeout: 20_000 });
  await expect(timer.getByTestId("suggestion").first()).toBeVisible({ timeout: 20_000 });
  await expect(timer.getByRole("button", { name: "Accept" })).toHaveCount(0);
  await expect(timer.getByRole("button", { name: "Dismiss" })).toHaveCount(0);
  await timerContext.close();
  for (let remaining = await missed.count(); remaining > 0; remaining--) {
    await missed.first().getByRole("button", { name: "Accept" }).click();
    await expect(missed).toHaveCount(remaining - 1, { timeout: 20_000 });
  }

  await expect(page.getByTestId("suggestion")).toHaveCount(0, { timeout: 20_000 });
  const statuses = page.getByTestId("rider-status");
  await expect(statuses).toHaveCount(12);
  await expect(statuses.filter({ hasNotText: "finished" })).toHaveCount(0);
});
