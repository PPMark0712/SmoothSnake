// Optional real-browser smoke test. Install: npm install --prefix .tools/browser playwright
// Start the local server first: python3 tools/web.py serve
const { chromium } = require("../.tools/browser/node_modules/playwright");
const fs = require("node:fs");
const assert = require("node:assert/strict");
const path = require("node:path");

(async () => {
  const output = path.resolve(__dirname, "../artifacts");
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(output, ".gdignore"), "");
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_BIN || undefined,
    headless: true,
    args: ["--enable-webgl", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => {
      if (message.type() === "error") errors.push(message.text());
    });
    await page.goto(process.env.GAME_URL || "http://127.0.0.1:8060");
    await page.locator("#status").waitFor({ state: "hidden", timeout: 30000 });
    await page.locator('canvas[data-state="ready"]').waitFor();
    assert.equal(errors.length, 0, errors.join("\n"));
    await page.screenshot({ path: path.join(output, "01-ready.png") });
    await page.keyboard.press("Enter");
    await page.locator('canvas[data-state="playing"]').waitFor();
    // Intentional elapsed gameplay: reach the first apple, then freeze the run.
    await page.locator('canvas[data-score="1"]').waitFor({ timeout: 8000 });
    await page.screenshot({ path: path.join(output, "06-playing.png") });
    await page.keyboard.press("Escape");
    await page.locator('canvas[data-state="paused"]').waitFor();
    await page.screenshot({ path: path.join(output, "02-paused.png") });
    const paused = await page.screenshot();
    await page.waitForTimeout(350);
    assert(paused.equals(await page.screenshot()), "Paused game must remain visually frozen");
    await page.keyboard.press("Escape");
    // With no steering the snake must eventually hit the right wall.
    await page.locator('canvas[data-state="over"]').waitFor({ timeout: 12000 });
    await page.screenshot({ path: path.join(output, "03-game-over.png") });
    await page.keyboard.press("r");
    await page.locator('canvas[data-state="playing"][data-score="0"]').waitFor();
    await page.keyboard.down("ArrowRight");
    // A held turn keeps the short snake circling until the first bomb appears.
    await page.waitForTimeout(10500);
    await page.screenshot({ path: path.join(output, "07-bomb.png") });
    await page.keyboard.up("ArrowRight");
    await page.keyboard.press("Escape");
    await page.locator('canvas[data-state="paused"]').waitFor();
    await page.screenshot({ path: path.join(output, "04-steering.png") });
    await page.setViewportSize({ width: 960, height: 600 });
    await page.screenshot({ path: path.join(output, "05-small.png") });
    const layout = await page.evaluate(() => ({
      canvas: { width: document.querySelector("canvas").clientWidth, height: document.querySelector("canvas").clientHeight },
      overflow: document.documentElement.scrollWidth > innerWidth,
    }));
    assert(!layout.overflow, "Game must fit viewport without horizontal scrolling");
    assert.deepEqual(layout.canvas, { width: 960, height: 600 });
    assert.equal(errors.length, 0, errors.join("\n"));
    fs.writeFileSync(path.join(output, "browser-results.json"), JSON.stringify({ errors, layout, screenshots: 7 }, null, 2));
    console.log("Browser smoke passed: load, start, pause/freeze, resume, death/restart, steering, resize; no console errors.");
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
