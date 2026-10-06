import { expect, test, type Page } from "@playwright/test";

const region = (page: Page, name: string) => page.getByRole("region", { name });

async function addRace(page: Page, fields: { category?: string; ageGroup?: string; gender: string; name?: string; laps?: string; finishWithLeader?: string }) {
  await page.getByRole("button", { name: "Add race" }).click();
  const dialog = page.getByRole("dialog");
  if (fields.category) await dialog.getByLabel("Category").fill(fields.category);
  if (fields.ageGroup) await dialog.getByLabel("Age group", { exact: true }).fill(fields.ageGroup);
  await dialog.getByLabel("Gender").selectOption(fields.gender);
  if (fields.name) await dialog.getByLabel("Name").fill(fields.name);
  await dialog.getByLabel("Scheduled start").fill("2026-10-18T18:00");
  if (fields.laps) await dialog.getByLabel("Expected laps").fill(fields.laps);
  if (fields.finishWithLeader) await dialog.getByLabel("Finish with leader").selectOption(fields.finishWithLeader);
  await dialog.getByRole("button", { name: "Save" }).click();
}

test("admin sets up a CX event and its races; lap count follows finish-with-leader cohorts", async ({ page }) => {
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Admin");
  await page.getByLabel("PIN").fill("9753");
  await page.getByRole("button", { name: "Sign in" }).click();

  await page.getByRole("button", { name: "New event" }).click();
  const create = page.getByRole("dialog");
  await create.getByLabel("Name").fill("Setup CX");
  await create.getByLabel("Date").fill("2026-10-18");
  await create.getByLabel("Location").fill("River Park");
  await create.getByLabel("Discipline").selectOption("cyclocross");
  await expect(create.getByLabel("Finish with leader")).toBeChecked();
  await expect(create.getByLabel("Age as of next year (cross season)")).toBeChecked();
  await create.getByRole("button", { name: "Create" }).click();
  await expect(page).toHaveURL(/\/console\/event\/[0-9a-f-]+\/setup$/);

  await addRace(page, { category: "Cat 3", ageGroup: "Masters 35+", gender: "men" });
  await expect(page.getByRole("row").filter({ hasText: "Cat 3 Masters 35+ Men" })).toBeVisible();
  await addRace(page, { gender: "women", name: "Women Open" });
  await addRace(page, { category: "Novice", gender: "open", laps: "3", finishWithLeader: "off" });
  await expect(page.getByRole("row").filter({ hasText: "Novice Open" })).toBeVisible();

  // Review Focus 2: a duplicate name is refused with the hub's message.
  await addRace(page, { category: "Cat 3", ageGroup: "Masters 35+", gender: "men" });
  await expect(page.getByRole("dialog").getByText("Name Cat 3 Masters 35+ Men is already used in this event")).toBeVisible();
  await page.getByRole("dialog").getByRole("button", { name: "Cancel" }).click();

  await page.getByRole("tab", { name: "Starts" }).click();
  for (const name of ["Cat 3 Masters 35+ Men", "Women Open", "Novice Open"]) {
    await page.getByRole("checkbox", { name: `Select ${name}` }).check();
  }
  await page.getByRole("button", { name: "Start", exact: true }).click();
  await expect(page.getByRole("row").filter({ hasText: "Novice Open" })).toContainText("Started");

  // Editing a started race without touching its start keeps the recorded start.
  await page.getByRole("tab", { name: "Setup" }).click();
  const novice = page.getByRole("row").filter({ hasText: "Novice Open" });
  const startedCell = novice.getByRole("cell").nth(6);
  await expect(startedCell).not.toHaveText("—");
  const recorded = await startedCell.textContent();
  await novice.getByRole("button", { name: "Edit Novice Open" }).click();
  await page.getByRole("dialog").getByLabel("Expected duration (minutes)").fill("40");
  await page.getByRole("dialog").getByLabel("First bib").fill("300");
  await page.getByRole("dialog").getByLabel("Last bib").fill("399");
  await page.getByRole("dialog").getByRole("button", { name: "Save" }).click();
  await expect(novice).toContainText("40 min");
  const bibRange = novice.getByRole("cell").nth(4);
  await expect(bibRange).toHaveText("300–399");
  await expect(bibRange).toHaveCSS("text-align", "center");
  await expect(novice.getByRole("button", { name: "Delete Novice Open" })).toBeVisible();
  await expect(page.getByRole("columnheader", { name: "Actions" })).toBeVisible();
  await expect(startedCell).toHaveText(recorded!);

  // Review Focus 1/5: laps set on one finish-with-leader race apply to its cohort only.
  await page.getByRole("tab", { name: "Results" }).click();
  await region(page, "Cat 3 Masters 35+ Men").getByLabel("Laps").fill("2");
  await region(page, "Cat 3 Masters 35+ Men").getByRole("button", { name: "Set laps" }).click();
  await expect(region(page, "Cat 3 Masters 35+ Men")).toContainText("2 laps");
  await expect(region(page, "Women Open")).toContainText("2 laps");
  await expect(region(page, "Novice Open")).toContainText("3 laps");
});
