import { expect, test, type Page } from "@playwright/test";

async function results(page: Page, name: string, pin: string) {
  await page.goto("/console/");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("PIN").fill(pin);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Officiating/ }).click();
  await page.getByRole("tab", { name: "Results" }).click();
}

const standingsRow = (page: Page, bib: string) =>
  page.getByRole("region", { name: "Masters 35+ Men" }).getByRole("row").filter({ has: page.getByRole("cell", { name: bib, exact: true }) });

async function openRacer(page: Page, bib: string) {
  await standingsRow(page, bib).click();
  const panel = page.getByTestId("racer-panel");
  await expect(panel).toContainText(`Bib ${bib}`);
  return panel;
}

async function crossingAction(panel: ReturnType<Page["getByTestId"]>, page: Page, index: number, action: string) {
  await panel.getByTestId("panel-crossing").nth(index).getByRole("button", { name: "Crossing actions" }).click();
  await page.getByRole("menuitem", { name: action }).click();
}

test("a chief fixes a racer's race from the racer panel; a timer sees it read-only", async ({ page, browser }) => {
  await results(page, "E2E Chief", "2468");

  // 101: four taps, one a duplicate (3 s after lap 2); positions per lap.
  let panel = await openRacer(page, "101");
  const crossings = panel.getByTestId("panel-crossing");
  await expect(crossings).toHaveCount(4);
  await expect(crossings.nth(2)).toContainText("duplicate");
  await expect(crossings.nth(0)).toContainText("1st");

  // Void the duplicate, then flag the last crossing as the finish.
  await crossingAction(panel, page, 2, "Void");
  await expect(crossings).toHaveCount(3);
  await crossingAction(panel, page, 2, "Finish here");
  await expect(panel.getByTestId("panel-status")).toHaveText("Finished");
  await panel.getByRole("button", { name: "Close" }).click();

  // 102: insert a missed crossing before its 2nd lap, then undo it.
  panel = await openRacer(page, "102");
  await expect(panel.getByTestId("panel-summary")).toContainText("2 laps");
  await crossingAction(panel, page, 1, "Insert missed crossing before");
  await page.getByRole("dialog", { name: "Insert crossing" }).getByRole("button", { name: "Insert" }).click();
  await expect(panel.getByTestId("panel-summary")).toContainText("3 laps");
  await expect(panel.getByTestId("panel-crossing").filter({ hasText: "inserted by E2E Chief" })).toHaveCount(1);
  const fix = panel.getByTestId("panel-fix").filter({ hasText: "Insert crossing" });
  await fix.getByRole("button", { name: "Undo" }).click();
  await page.getByRole("dialog", { name: /Undo/ }).getByRole("button", { name: "Undo" }).click();
  await expect(panel.getByTestId("panel-summary")).toContainText("2 laps");
  await expect(fix).toContainText("undone by E2E Chief");
  await panel.getByRole("button", { name: "Close" }).click();

  // 103: pull at its only crossing; the panel survives a reload.
  panel = await openRacer(page, "103");
  await crossingAction(panel, page, 0, "Pull here");
  await expect(panel.getByTestId("panel-status")).toHaveText("Pulled");
  await page.reload();
  await expect(page.getByTestId("racer-panel")).toContainText("Bib 103");

  // History (Problems tab): every fix, searchable, with Undo and a link to the racer.
  await page.getByTestId("racer-panel").getByRole("button", { name: "Close" }).click();
  await page.getByRole("tab", { name: /Problems/ }).click();
  await page.getByRole("button", { name: "History" }).click();
  const history = page.getByTestId("history-entry");
  await expect(history.filter({ hasText: "Pull bib 103" })).toContainText("E2E Chief");
  await expect(history.filter({ hasText: "Void crossing" })).toHaveCount(1);
  await page.getByLabel("Search history").fill("103");
  await expect(history).toHaveCount(1);
  const pull = history.filter({ hasText: "Pull bib 103" }).filter({ hasNotText: "Undo:" });
  await pull.getByRole("button", { name: "Undo" }).click();
  await page.getByRole("dialog", { name: /Undo/ }).getByRole("button", { name: "Undo" }).click();
  await expect(pull).toContainText("undone by E2E Chief");
  await expect(history.filter({ hasText: "Undo: Pull bib 103" })).toHaveCount(1);
  await expect(history.filter({ hasText: "Undo: Pull bib 103" }).getByRole("button", { name: "Undo" })).toHaveCount(0);
  await pull.getByRole("button", { name: "Bib 103" }).click();
  await expect(page.getByTestId("racer-panel")).toContainText("Bib 103");
  await expect(page.getByTestId("racer-panel").getByTestId("panel-status")).toHaveText("Racing");

  // An unknown bib says so.
  await page.goto(page.url().replace(/racer=103/, "racer=999"));
  await expect(page.getByTestId("racer-panel")).toContainText("No racer with bib 999 in this event");

  // A timer sees the summary, without any fixing controls.
  const timer = await (await browser.newContext()).newPage();
  await results(timer, "E2E Timer", "1357");
  const readOnly = await openRacer(timer, "101");
  await expect(readOnly.getByTestId("panel-crossing")).toHaveCount(3);
  await expect(readOnly.getByRole("button", { name: "Crossing actions" })).toHaveCount(0);
  await expect(readOnly.getByRole("button", { name: "Insert crossing at…" })).toHaveCount(0);
  await expect(readOnly.getByRole("button", { name: "Undo" })).toHaveCount(0);
  await expect(readOnly.getByRole("button", { name: "Racer actions" })).toHaveCount(0);
});
