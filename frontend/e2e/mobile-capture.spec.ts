import { devices, expect, test, type Browser, type Page } from "@playwright/test";

async function chiefOnCapture(browser: Browser): Promise<Page> {
  const page = await (await browser.newContext()).newPage();
  await page.goto("/console/");
  await page.getByLabel("Name").fill("E2E Chief");
  await page.getByLabel("PIN").fill("2468");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: /E2E Capture/ }).click();
  await page.getByRole("tab", { name: "Capture" }).click();
  return page;
}

test("a phone records offline, syncs when back, and picks up the hub's fixes", async ({ browser }) => {
  const chief = await chiefOnCapture(browser);
  await chief.getByRole("button", { name: "Pair a phone" }).click();
  const link = new URL((await chief.getByTestId("pairing-link").textContent())!);
  await chief.getByRole("button", { name: "Done" }).click();

  // 1. Pair a phone-sized browser from the link.
  const phoneContext = await browser.newContext({ ...devices["Pixel 7"], baseURL: "http://127.0.0.1:3200" });
  const phone = await phoneContext.newPage();
  await phone.goto(`${link.pathname}${link.search}`);
  await phone.getByLabel("Phone name").fill("Finish phone");
  await phone.getByRole("button", { name: "Pair" }).click();
  await expect(phone.getByRole("button", { name: "Enter" })).toBeVisible();
  expect(phone.url()).not.toContain("pair=");
  await expect(phone.getByTestId("sync-pill")).toHaveText("Synced", { timeout: 20_000 });

  const key = (k: string) => phone.getByRole("button", { name: k, exact: true }).click();
  const type = async (digits: string) => { for (const d of digits) await key(d); };
  const pill = phone.getByTestId("sync-pill");
  const rows = phone.getByTestId("crossing");

  // 2. Offline: three taps, a correction and a delete stay on the phone.
  await phoneContext.setOffline(true);
  await type("101");
  await key("Enter");
  await key("Enter");
  await type("999");
  await key("Enter");
  await expect(rows).toHaveCount(3);
  await expect(pill).toHaveText(/Offline · 3 to send/, { timeout: 20_000 });
  await rows.filter({ hasText: "101" }).getByRole("button", { name: "Show only this bib" }).click();
  await expect(rows).toHaveCount(1);
  await phone.getByRole("button", { name: "Bib 101" }).locator("svg").click();
  await expect(rows).toHaveCount(3);

  await rows.filter({ hasText: "999" }).getByRole("button", { name: "Edit bib" }).click();
  const sheet = phone.getByRole("dialog", { name: "Correct bib" });
  for (const d of "102") await sheet.getByRole("button", { name: d, exact: true }).click();
  await sheet.getByRole("button", { name: "Save" }).click();
  await expect(rows.filter({ hasText: "entered: 999" })).toContainText("102");

  await rows.filter({ hasText: "No bib" }).getByRole("button", { name: "Delete crossing" }).click();
  await phone.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await expect(rows).toHaveCount(2);
  await expect(pill).toHaveText(/Offline · 5 to send/);

  // 3. Back online: everything reaches the hub.
  await phoneContext.setOffline(false);
  await expect(pill).toHaveText("Synced", { timeout: 30_000 });
  await chief.reload();
  await expect(chief.getByTestId("phone").filter({ hasText: "Finish phone" })).toBeVisible();
  // The console log shows the phone's crossings; a chief corrects one as an official.
  const consoleRows = chief.getByTestId("capture").filter({ hasText: "Finish phone" });
  await expect(consoleRows).toHaveCount(2);
  await consoleRows.filter({ hasText: "101" }).getByRole("button", { name: "Edit bib" }).click();
  await chief.getByLabel("Bib for crossing").fill("103");
  await chief.getByLabel("Bib for crossing").press("Enter");
  await expect(consoleRows.filter({ hasText: "entered: 101" })).toContainText("103");
  await expect(rows.filter({ hasText: "entered: 101" })).toContainText("103", { timeout: 20_000 });
  await expect(rows.filter({ hasText: "entered: 101" }).getByRole("button", { name: "Edit bib" })).toBeDisabled();

  await chief.getByRole("tab", { name: "Results" }).click();
  await expect(chief.getByTestId("suggestion").filter({ hasText: /No bib · / })).toHaveCount(0);

  // 4. A no-bib crossing fixed on the hub shows on the phone after its next sync.
  await key("Enter");
  await expect(pill).toHaveText("Synced", { timeout: 30_000 });
  const loose = chief.getByTestId("suggestion").filter({ hasText: /No bib · / });
  await expect(loose).toHaveCount(1, { timeout: 20_000 });
  await loose.getByLabel("Bib").fill("103");
  await loose.getByRole("button", { name: "Accept" }).click();
  await expect(rows.filter({ hasText: "entered: no bib" })).toContainText("103", { timeout: 20_000 });

  // Layout: only the log scrolls; in landscape the keypad sits beside it.
  const enterKey = phone.getByRole("button", { name: "Enter" });
  const log = phone.getByTestId("crossing-log");
  const pageScrolls = () => phone.evaluate(() => document.scrollingElement!.scrollHeight > window.innerHeight + 1);
  expect(await pageScrolls()).toBe(false);
  await expect(log).toHaveCSS("overflow-y", "auto");
  await phone.setViewportSize({ width: 915, height: 412 });
  expect(await pageScrolls()).toBe(false);
  const keypadBox = (await enterKey.boundingBox())!;
  const logBox = (await log.boundingBox())!;
  expect(keypadBox.x + keypadBox.width).toBeLessThanOrEqual(logBox.x + 1);

  // The correction sheet fits a short landscape screen (iPhone: 844 x 390).
  await phone.setViewportSize({ width: 844, height: 390 });
  for (const name of ["0", "Enter"]) {
    const box = (await phone.getByRole("button", { name, exact: true }).first().boundingBox())!;
    expect(box.y + box.height, `main ${name} is on screen`).toBeLessThanOrEqual(390);
  }
  await rows.filter({ hasText: "entered: 999" }).getByRole("button", { name: "Edit bib" }).click();
  const editSheet = phone.getByRole("dialog", { name: "Correct bib" });
  for (const name of ["1", "0", "Backspace", "Save", "Cancel"]) {
    const box = (await editSheet.getByRole("button", { name, exact: true }).boundingBox())!;
    expect(box.y + box.height, `${name} is on screen`).toBeLessThanOrEqual(390);
  }
  await editSheet.getByRole("button", { name: "Cancel" }).click();
  await phone.setViewportSize({ width: 412, height: 915 });

  // 5. Revoked on the console: the phone says so, rather than just "Offline".
  await chief.getByRole("tab", { name: "Capture" }).click();
  await chief.getByTestId("phone").filter({ hasText: "Finish phone" }).getByRole("button", { name: "Revoke Finish phone" }).click();
  await chief.getByRole("dialog").getByRole("button", { name: "Revoke" }).click();
  await expect(pill).toHaveText("Revoked", { timeout: 20_000 });
  await expect(phone.getByText("This phone was revoked on the hub")).toBeVisible();
});
