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
const counts = (page: Page) => page.getByTestId("registration-counts");

test("admin imports a BikeReg export and assigns bibs; a chief adds a walk-up and checks riders in", async ({ page }) => {
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
  await expect(counts(page)).toHaveText("5 registered · 0 checked in · 4 need a bib");

  // Assign bibs: Cat 3 Men from 100–199, everyone else from the event's 1–99.
  await page.getByRole("button", { name: "Assign bibs" }).click();
  await expect(page.getByText("Assigned 4 bibs")).toBeVisible();
  await expect(row(page, "Di Eve").getByLabel("Bib for Di Eve")).toHaveValue("100");
  await expect(row(page, "Di Eve").getByLabel("Bib for Di Eve")).toHaveCSS("text-align", "center");
  await expect(row(page, "Di Eve").getByRole("button", { name: "Edit Di Eve" })).toBeVisible();
  await expect(row(page, "Di Eve").getByRole("button", { name: "Remove Di Eve" })).toBeVisible();
  await expect(row(page, "Ann Lee").getByLabel("Bib for Ann Lee")).not.toHaveValue("");
  await expect(counts(page)).toHaveText("5 registered · 0 checked in · 0 need a bib");

  // Day-of as a chief: a walk-up without a bib, a check-in, then a bib typed in the row.
  await page.getByRole("button", { name: "Sign out" }).click();
  await openRegistration(page, "E2E Chief", "2468");
  await expect(page.getByRole("button", { name: "Import" })).toHaveCount(0);
  await page.getByRole("button", { name: "Add rider" }).click();
  const walkUp = page.getByRole("dialog", { name: "Add rider" });
  await walkUp.getByLabel("First name").fill("Walk");
  await walkUp.getByLabel("Last name").fill("Up");
  await walkUp.getByLabel("Gender").selectOption("M");
  await walkUp.getByLabel("Race").selectOption({ label: "Cat 3 Men" });
  await walkUp.getByRole("button", { name: "Save" }).click();
  await expect(row(page, "Walk Up")).toContainText("needs bib");
  await expect(row(page, "Walk Up").getByRole("checkbox", { name: "Checked in Walk Up" })).toBeChecked();

  await row(page, "Ann Lee").getByRole("checkbox", { name: "Checked in Ann Lee" }).check();
  await expect(counts(page)).toHaveText("6 registered · 2 checked in · 1 needs a bib");

  // A half-typed bib is not saved when you click away; only Enter saves.
  const diBib = row(page, "Di Eve").getByLabel("Bib for Di Eve");
  await diBib.fill("9");
  await page.getByLabel("Search").click();
  await expect(diBib).toHaveValue("100");

  const bib = row(page, "Walk Up").getByLabel("Bib for Walk Up");
  await bib.fill("150");
  await bib.press("Enter");
  await expect(row(page, "Walk Up")).not.toContainText("needs bib");
  await expect(counts(page)).toHaveText("6 registered · 2 checked in · 0 need a bib");
});
