import { expect, test, type Page } from "@playwright/test";
import path from "node:path";

const FIXTURE = path.resolve(import.meta.dirname, "fixtures/bikereg_export.csv");

async function openRegistration(page: Page, name: string, pin: string) {
  await page.goto("/console/");
  await page.getByLabel("Name").fill(name);
  await page.getByLabel("PIN").fill(pin);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Registration/ }).click();
  await page.getByRole("tab", { name: "Registration" }).click();
}

const row = (page: Page, name: string) => page.getByTestId("registration").filter({ hasText: name });
// The stat tiles over the table: racers, checked in, and racers still needing a bib.
async function expectStats(page: Page, racers: string, checkedIn: string, needsBib: string) {
  await expect(page.getByTestId("stat-racers")).toHaveAccessibleName(racers);
  await expect(page.getByTestId("stat-checked-in")).toHaveAccessibleName(checkedIn);
  await expect(page.getByTestId("stat-needs-bib")).toHaveAccessibleName(needsBib);
}

test("admin imports a BikeReg export and assigns bibs; a chief adds a walk-up and checks racers in", async ({ page }) => {
  await openRegistration(page, "E2E Admin", "9753");

  // Import: columns are matched automatically; categories are mapped, skipped or made into a new race.
  await page.getByRole("button", { name: "Import" }).click();
  const dialog = page.getByRole("dialog", { name: "Import registrations" });
  await dialog.getByLabel("CSV file").setInputFiles(FIXTURE);
  await expect(dialog.getByLabel("Category column")).toHaveValue("Category Entered / Merchandise Ordered");
  await expect(dialog.getByLabel("Race for Women Open")).toHaveValue(/.+/);
  await dialog.getByLabel("Race for T-Shirt").selectOption("skip");
  await dialog.getByLabel("Race for Masters 50+ Men Cat 1/2/3").selectOption("create");
  const raceDialog = page.getByRole("dialog", { name: "Add race" });
  await expect(raceDialog.getByLabel("Name")).toHaveValue("Masters 50+ Men Cat 1/2/3");
  await raceDialog.getByLabel("Scheduled start").fill("2026-10-18T18:00");
  await raceDialog.getByRole("button", { name: "Save" }).click();
  await expect(dialog.getByLabel("Race for Masters 50+ Men Cat 1/2/3")).not.toHaveValue("create");

  await dialog.getByRole("button", { name: "Preview" }).click();
  await expect(dialog).toContainText("5 new · 0 updated · 1 skipped · 0 errors");
  await dialog.getByRole("button", { name: "Import", exact: true }).click();
  await expect(dialog).toContainText("Imported 5 new · 0 updated · 1 skipped");
  await dialog.getByRole("button", { name: "Done" }).click();

  await expect(page.getByTestId("registration")).toHaveCount(5);
  await expect(row(page, "Ann Lee")).toContainText("needs bib");
  await expect(row(page, "Bob Ray")).not.toContainText("needs bib");
  await expectStats(page, "5 racers", "0 of 5 checked in", "4 need a bib");

  // The need-bib tile is a shortcut to its filter (and back).
  await page.getByTestId("stat-needs-bib").click();
  await expect(page.getByRole("checkbox", { name: "Needs bib" })).toBeChecked();
  await expect(page.getByTestId("registration")).toHaveCount(4);
  await page.getByTestId("stat-needs-bib").click();
  await expect(page.getByTestId("registration")).toHaveCount(5);

  // Assign bibs for one race from Setup: Cat 3 Men from its 100–199.
  await page.getByRole("tab", { name: "Setup" }).click();
  await page.getByRole("button", { name: "Assign bibs for Cat 3 Men" }).click();
  await expect(page.getByText("Cat 3 Men: assigned 1 bib")).toBeVisible();
  await page.getByRole("tab", { name: "Registration" }).click();
  await expectStats(page, "5 racers", "0 of 5 checked in", "3 need a bib");

  // Then the rest of the event from the Registration toolbar, from the event's 1–99.
  await page.getByRole("button", { name: "Assign bibs" }).click();
  await expect(page.getByText("Assigned 3 bibs")).toBeVisible();
  await expect(row(page, "Di Eve").getByLabel("Bib for Di Eve")).toHaveValue("100");
  await expect(row(page, "Di Eve").getByLabel("Bib for Di Eve")).toHaveCSS("text-align", "center");
  await expect(row(page, "Di Eve").getByRole("button", { name: "Edit Di Eve" })).toBeVisible();
  await expect(row(page, "Di Eve").getByRole("button", { name: "Remove Di Eve" })).toBeVisible();
  await expect(page.getByRole("columnheader", { name: "Actions" })).toBeVisible();
  await expect(row(page, "Ann Lee").getByLabel("Bib for Ann Lee")).not.toHaveValue("");
  await expectStats(page, "5 racers", "0 of 5 checked in", "0 need a bib");

  // Search and race take several values, shown as chips, and survive a refresh.
  const search = page.getByLabel("Search");
  await search.fill("eve");
  await search.press("Enter");
  await search.fill("gee");
  await search.press("Enter");
  await expect(page.getByRole("button", { name: "eve", exact: true })).toBeVisible();
  await expect(page.getByTestId("registration")).toHaveCount(2);
  await page.getByRole("combobox", { name: "Race" }).click();
  await page.getByRole("option", { name: "Women Open" }).click();
  await page.keyboard.press("Escape");
  await expect(page.getByTestId("registration")).toHaveCount(1);
  await page.getByRole("checkbox", { name: "Not checked in" }).check();
  await expectStats(page, "1 of 5 racers", "0 of 1 checked in", "0 need a bib");
  await page.reload();
  await expect(page.getByRole("button", { name: "gee", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Women Open", exact: true })).toBeVisible();
  await expect(page.getByRole("checkbox", { name: "Not checked in" })).toBeChecked();
  await expect(page.getByTestId("registration")).toHaveCount(1);
  await expect(page.getByTestId("registration")).toContainText("Flo Gee");
  await page.getByRole("button", { name: "Clear filters" }).click();
  await expect(page.getByTestId("registration")).toHaveCount(5);

  // Columns sort; a second click reverses, and the sort survives a refresh.
  await page.getByRole("button", { name: "Name" }).click();
  await expect(page.getByTestId("registration").first()).toContainText("Cy Dee");
  await page.getByRole("button", { name: "Name" }).click();
  await expect(page.getByTestId("registration").first()).toContainText("Bob Ray");
  await page.reload();
  await expect(page.getByTestId("registration").first()).toContainText("Bob Ray");

  // Day-of as a chief: a walk-up without a bib, a check-in, then a bib typed in the row.
  await page.getByRole("button", { name: "Sign out" }).click();
  await openRegistration(page, "E2E Chief", "2468");
  await expect(page.getByRole("button", { name: "Import" })).toHaveCount(0);
  await page.getByRole("button", { name: "Add racer" }).click();
  const walkUp = page.getByRole("dialog", { name: "Add racer" });
  await walkUp.getByLabel("First name").fill("Walk");
  await walkUp.getByLabel("Last name").fill("Up");
  await walkUp.getByLabel("Gender").selectOption("M");
  await walkUp.getByLabel("Race").selectOption({ label: "Cat 3 Men" });
  await walkUp.getByRole("button", { name: "Save" }).click();
  await expect(row(page, "Walk Up")).toContainText("needs bib");
  await expect(row(page, "Walk Up").getByRole("checkbox", { name: "Checked in Walk Up" })).toBeChecked();

  // A no-show is marked DNS from their row, and it can be cleared.
  await row(page, "Bob Ray").getByRole("button", { name: "Mark DNS for Bob Ray" }).click();
  await expect(row(page, "Bob Ray").getByTestId("official-status")).toHaveText("DNS");
  await row(page, "Bob Ray").getByRole("button", { name: "Clear DNS for Bob Ray" }).click();
  await expect(row(page, "Bob Ray").getByTestId("official-status")).toHaveCount(0);

  await row(page, "Ann Lee").getByRole("checkbox", { name: "Checked in Ann Lee" }).check();
  await expectStats(page, "6 racers", "2 of 6 checked in", "1 needs a bib");

  // Tab saves a bib like Enter; a duplicate shows the hub's error and keeps what
  // was typed until it's fixed, and Escape puts the saved bib back.
  const diBib = row(page, "Di Eve").getByLabel("Bib for Di Eve");
  await diBib.fill("12");
  await diBib.press("Tab");
  await expect(row(page, "Di Eve")).toContainText("Bib has already been taken");
  await expect(diBib).toHaveValue("12");
  await diBib.press("Escape");
  await expect(diBib).toHaveValue("100");
  await expect(row(page, "Di Eve")).not.toContainText("Bib has already been taken");
  await diBib.fill("101");
  await diBib.press("Tab");
  await expect(row(page, "Di Eve")).not.toContainText("already");
  await page.reload();
  await expect(row(page, "Di Eve").getByLabel("Bib for Di Eve")).toHaveValue("101");

  const bib = row(page, "Walk Up").getByLabel("Bib for Walk Up");
  await bib.fill("150");
  await bib.press("Enter");
  await expect(row(page, "Walk Up")).not.toContainText("needs bib");
  // Checked in with a bib: the bib is locked.
  await expect(row(page, "Walk Up").getByLabel("Bib for Walk Up")).toBeDisabled();
  await expectStats(page, "6 racers", "2 of 6 checked in", "0 need a bib");
});
