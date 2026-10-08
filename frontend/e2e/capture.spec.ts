import { expect, test } from "@playwright/test";

test("a timer records crossings by bib, or with no bib for review", async ({ page, browser }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Timer");
  await page.getByLabel("PIN").fill("1357");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();

  // The log shows every device's crossings; this timer looks at their own.
  await page.getByLabel("Device").selectOption("mine");
  const bib = page.getByLabel("Bib", { exact: true });
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
  await expect(rows.filter({ hasText: "999" }).getByTestId("bib-problem")).toHaveText("Unknown bib");
  await expect(rows.filter({ hasText: "no bib" })).toHaveCount(1);
  await expect(lap3).toContainText("101");
  await expect(lap3).toContainText("Masters 35+ Men");
  await expect(lap3.getByTestId("lap-warning")).toContainText("Long lap");
  await expect(lap3.getByTestId("lap-warning")).toHaveAccessibleName(/typical 1:00\.0/);

  // Filter to one bib from the icon at the start of a row; the chip clears it.
  await expect(page.getByText("Type the bib and press Enter as the racer crosses")).toBeVisible();
  await lap4.getByRole("button", { name: "Show only this bib" }).click();
  await expect(rows).toHaveCount(2);
  await page.getByRole("button", { name: "Bib 101" }).locator("svg").click();
  await expect(rows).toHaveCount(5);

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

test("flag out from the line: the hub picks the wave on course; a chief can undo it", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();

  // Masters 35+ Men is the only race on course (seed), so its wave is the one flagged.
  await page.getByRole("button", { name: "Flag out", exact: true }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toContainText("Masters 35+ Men");
  await dialog.getByRole("button", { name: "Flag out" }).click();
  const banner = page.getByTestId("flag-out-banner");
  await expect(banner).toContainText(/Flag out at \d\d:\d\d:\d\d: .* wave/);
  // A mistaken flag is undone right from the banner (chiefs), then put out again.
  await banner.getByRole("button", { name: "Undo" }).click();
  await expect(banner).toHaveCount(0);
  await page.getByRole("button", { name: "Flag out", exact: true }).click();
  await dialog.getByRole("button", { name: "Flag out" }).click();
  await expect(banner).toContainText("Flag out at");

  await page.getByRole("tab", { name: "Results" }).click();
  await expect(page.getByRole("region", { name: "Masters 35+ Men" }).getByTestId("flag-out")).toBeVisible();
  await page.getByRole("tab", { name: "Capture" }).click();

  // Nothing else is on course, so a second press says so (the banner kept the undo).
  await page.getByRole("button", { name: "Flag out", exact: true }).click();
  await expect(banner).toContainText("No wave on course to flag");
  await page.getByRole("tab", { name: "Results" }).click();
  await page.getByRole("tab", { name: "Problems" }).click();
  await page.getByRole("button", { name: "History" }).click();
  const flag = page.getByTestId("history-entry").filter({ hasText: /^.*Flag out for/ }).filter({ hasNotText: "Undo:" }).first(); // newest first
  await flag.getByRole("button", { name: "Undo" }).click();
  await page.getByRole("dialog", { name: /Undo/ }).getByRole("button", { name: "Undo" }).click();
  await expect(flag).toContainText("undone by E2E Chief");
});
