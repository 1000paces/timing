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

test("chief starts races in waves, unstarts a mistake, runs the race and clears the review queue", async ({ page, browser }) => {
  // Review Focus 3: a timer, watching alongside, never gets action buttons.
  const timerContext = await browser.newContext();
  const timer = await timerContext.newPage();
  await openEvent(timer, "E2E Timer", "1357");
  await expect(timer.getByRole("heading", { name: "Starts" })).toBeVisible();
  await expect(timer.getByRole("button", { name: "Start" })).toHaveCount(0);
  await expect(timer.getByRole("checkbox")).toHaveCount(0);

  await openEvent(page, "E2E Chief", "2468");
  const start = page.getByRole("button", { name: "Start", exact: true });
  await expect(start).toBeDisabled();

  // Wave 1: the two Masters races together. A double-click must not start anything twice.
  await page.getByRole("checkbox", { name: "Select Masters 35+ Men" }).check();
  await page.getByRole("checkbox", { name: "Select Masters 50+ Men" }).check();
  await start.dblclick();
  const row = (name: string) => page.getByRole("row").filter({ hasText: name });
  await expect(row("Masters 35+ Men")).toContainText("Started");
  await expect(row("Masters 50+ Men")).toContainText("Started");
  await expect(page.getByRole("checkbox", { name: "Select Masters 35+ Men" })).toBeDisabled();
  await expect(start).toBeDisabled();

  // The Start screen has its own address and survives a reload.
  await expect(page).toHaveURL(/\/console\/event\/[0-9a-f-]+\/starts$/);
  await page.reload();
  await expect(row("Masters 35+ Men")).toContainText("Started");

  await expect(page.getByRole("columnheader", { name: "Actions" })).toBeVisible();

  // Wave 2, started by mistake, then unstarted and started again.
  await page.getByRole("checkbox", { name: "Select Women Open" }).check();
  await start.click();
  await expect(row("Women Open")).toContainText("Started");
  await row("Women Open").getByRole("button", { name: "Unstart" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Unstart" }).click();
  await expect(row("Women Open")).toContainText("Not started");
  await page.getByRole("checkbox", { name: "Select Women Open" }).check();
  await start.click();
  await expect(row("Women Open")).toContainText("Started");

  // Race screen: lap count, then the race itself.
  await page.getByRole("tab", { name: "Results" }).click();
  // The demo races all finish with the leader and share a scheduled start, so
  // one lap count covers all three.
  const masters35 = page.getByRole("region", { name: "Masters 35+ Men" });
  await masters35.getByLabel("Laps").fill("3");
  await masters35.getByRole("button", { name: "Set laps" }).click();
  for (const name of ["Masters 35+ Men", "Masters 50+ Men", "Women Open"]) {
    await expect(page.getByRole("region", { name })).toContainText("3 laps");
  }

  const output = simulateRace();
  expect(output).toContain("set_race_start rulings: 4");

  const missed = page.getByTestId("suggestion").filter({ hasText: "missed crossing" });
  await expect(missed.first()).toBeVisible({ timeout: 20_000 });
  await expect(page.getByRole("heading", { name: "Review Queue" })).toBeVisible();
  await expect(missed.first().getByTestId("problem-type")).toHaveText("Missed crossing");
  await expect(page.getByTestId("issue-count").first()).toHaveText(/^\d+ issues?$/);

  // Problems tab: the same queue, full page, filterable by type (kept on refresh).
  await page.getByRole("tab", { name: /Problems/ }).click();
  await expect(page.getByTestId("issue-count").first()).toHaveText(/^\d+ issues?$/);
  await page.getByRole("combobox", { name: "Type" }).click();
  await page.getByRole("option", { name: /^Missed crossing/ }).click();
  await page.keyboard.press("Escape");
  await expect(page.getByTestId("issue-count").first()).toHaveText(/^\d+ of \d+ issues$/);
  await expect(page.getByTestId("problem-type").filter({ hasNotText: "Missed crossing" })).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole("button", { name: "Missed crossing", exact: true })).toBeVisible();
  await expect(page.getByTestId("problem-type").filter({ hasNotText: "Missed crossing" })).toHaveCount(0);
  await page.getByRole("tab", { name: "Results" }).click();
  await timer.getByRole("tab", { name: "Results" }).click();
  await expect(timer.getByTestId("suggestion").first()).toBeVisible({ timeout: 20_000 });
  await expect(timer.getByRole("button", { name: "Accept" })).toHaveCount(0);
  await expect(timer.getByRole("button", { name: "Dismiss" })).toHaveCount(0);
  await timerContext.close();

  for (let remaining = await missed.count(); remaining > 0; remaining--) {
    await missed.first().getByRole("button", { name: "Accept" }).click();
    await expect(missed).toHaveCount(remaining - 1, { timeout: 20_000 });
  }

  await expect(page.getByTestId("suggestion")).toHaveCount(0, { timeout: 20_000 });
  const statuses = page.getByTestId("racer-status");
  await expect(statuses).toHaveCount(12);
  await expect(statuses.filter({ hasNotText: "Finished" })).toHaveCount(0);

  // A chief marks a racer DNF from the Results row menu, then clears it.
  await page.getByRole("button", { name: /^Status actions for / }).first().click();
  await page.getByRole("menuitem", { name: "Mark DNF" }).click();
  const dnfRow = page.getByRole("row").filter({ has: page.getByTestId("racer-status").filter({ hasText: "DNF" }) });
  await expect(dnfRow).toHaveCount(1);
  await dnfRow.getByRole("button", { name: /^Status actions for / }).click();
  await page.getByRole("menuitem", { name: "Clear DNF" }).click();
  await expect(statuses.filter({ hasText: "DNF" })).toHaveCount(0);

  // DSQ the same way.
  await page.getByRole("button", { name: /^Status actions for / }).first().click();
  await page.getByRole("menuitem", { name: "Mark DSQ" }).click();
  const dsqRow = page.getByRole("row").filter({ has: page.getByTestId("racer-status").filter({ hasText: "DSQ" }) });
  await expect(dsqRow).toHaveCount(1);
  await dsqRow.getByRole("button", { name: /^Status actions for / }).click();
  await page.getByRole("menuitem", { name: "Clear DSQ" }).click();
  await expect(statuses.filter({ hasText: "DSQ" })).toHaveCount(0);
  await expect(statuses.filter({ hasNotText: "Finished" })).toHaveCount(0);
});
