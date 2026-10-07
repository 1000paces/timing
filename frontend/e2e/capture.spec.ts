import { expect, test } from "@playwright/test";

test("a timer records crossings by bib, or with no bib for review", async ({ page, browser }) => {
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
  // Each Enter is sent at once, so quick entries can reach the hub in either
  // order; find rows by what they show, not by position.
  const rows = page.getByTestId("capture");
  await expect(rows).toHaveCount(5);
  const lap3 = rows.filter({ hasText: "Lap 3" });
  const lap4 = rows.filter({ hasText: "Lap 4" });
  await expect(rows.filter({ hasText: "201" })).not.toContainText("Lap");
  await expect(lap4).toContainText("101");
  await expect(lap4.getByTestId("lap-warning")).toContainText("Short lap");
  await expect(rows.filter({ hasText: "999" })).toContainText("unknown bib");
  await expect(rows.filter({ hasText: "no bib" })).toHaveCount(1);
  await expect(lap3).toContainText("101");
  await expect(lap3).toContainText("Masters 35+ Men");
  await expect(lap3.getByTestId("lap-warning")).toContainText("Long lap");
  await expect(lap3.getByTestId("lap-warning")).toContainText("typical 1:00.0");

  // Deleting the earlier 101 crossing (after a confirm) renumbers the later one.
  await lap3.getByRole("button", { name: "Delete capture" }).click();
  const confirm = page.getByRole("dialog");
  await expect(confirm).toContainText("Delete bib 101 at");
  await confirm.getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(4);
  await expect(rows.filter({ hasText: "101" })).toContainText("Lap 3");

  // The bib-less crossing waits in the review queue on the Results tab.
  await page.getByRole("tab", { name: "Results" }).click();
  const queue = page.getByTestId("suggestion");
  await expect(queue.filter({ hasText: /No bib · \d\d:\d\d:\d\d · \+\d+:\d\d\.\d/ })).toHaveCount(1);
  await expect(queue.filter({ hasText: "Unknown racer: bib 999 · " })).toHaveCount(1);

  // A chief resolves the no-bib crossing; the timer's Capture list updates live.
  await page.getByRole("tab", { name: "Capture" }).click();
  const chiefContext = await browser.newContext();
  const chief = await chiefContext.newPage();
  await chief.goto("/console/");
  await chief.getByLabel("Name").fill("E2E Chief");
  await chief.getByLabel("PIN").fill("2468");
  await chief.getByRole("button", { name: "Sign in" }).click();
  await chief.getByRole("link", { name: /E2E Capture/ }).click();
  await chief.getByRole("tab", { name: "Results" }).click();
  const loose = chief.getByTestId("suggestion").filter({ hasText: /No bib · / });
  await loose.getByLabel("Bib").fill("102");
  await loose.getByRole("button", { name: "Accept" }).click();
  await expect(loose).toHaveCount(0);
  await chiefContext.close();

  const resolved = rows.filter({ hasText: "entered: no bib" });
  await expect(resolved).toContainText("102");
  await expect(rows.filter({ hasText: "no bib" }).filter({ hasNotText: "entered" })).toHaveCount(0);
  // An official's assignment locks the timer's own correction.
  await expect(resolved.getByRole("button", { name: "Edit bib" })).toBeDisabled();

  // The timer corrects a mistyped bib in the log; the tap keeps what was entered.
  await rows.filter({ hasText: "unknown bib" }).getByRole("button", { name: "Edit bib" }).click();
  const field = page.getByLabel("Bib for crossing");
  await field.fill("103");
  await field.press("Enter");
  const corrected = rows.filter({ hasText: "entered: 999" });
  await expect(corrected).toContainText("103");
  await expect(corrected).toContainText("Masters 35+ Men");
  await expect(page.getByLabel("Bib for crossing")).toHaveCount(0);
});
