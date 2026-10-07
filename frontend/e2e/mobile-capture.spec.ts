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

  // 5. Revoked on the console: the phone says so, rather than just "Offline".
  await chief.getByRole("tab", { name: "Capture" }).click();
  await chief.getByTestId("phone").filter({ hasText: "Finish phone" }).getByRole("button", { name: "Revoke Finish phone" }).click();
  await chief.getByRole("dialog").getByRole("button", { name: "Revoke" }).click();
  await expect(pill).toHaveText("Revoked", { timeout: 20_000 });
  await expect(phone.getByText("This phone was revoked on the hub")).toBeVisible();
});
