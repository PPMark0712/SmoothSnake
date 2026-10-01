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
    // Observe actual WebAudio output without calling into the game's internals.
    await page.addInitScript(() => {
      const connect = AudioNode.prototype.connect;
      const meters = [];
      AudioNode.prototype.connect = function (destination, ...args) {
        const result = connect.call(this, destination, ...args);
        if (destination instanceof AudioDestinationNode) {
          const meter = this.context.createAnalyser();
          meter.fftSize = 2048;
          connect.call(this, meter);
          meters.push(meter);
        }
        return result;
      };
      window.audioRms = () => Math.max(0, ...meters.map(meter => {
        const samples = new Float32Array(meter.fftSize);
        meter.getFloatTimeDomainData(samples);
        return Math.sqrt(samples.reduce((sum, value) => sum + value * value, 0) / samples.length);
      }));
    });
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
    await page.keyboard.press("d");
    await page.screenshot({ path: path.join(output, "08-debug-lines.png") });
    await page.keyboard.press("d");
    await page.keyboard.press("Enter");
    await page.locator('canvas[data-state="playing"]').waitFor();
    await page.waitForFunction(() => window.audioRms() > 0.0001, { }, { timeout: 8000 });
    // Intentional elapsed gameplay: reach the first apple, then freeze the run.
    await page.locator('canvas[data-score="1"]').waitFor({ timeout: 8000 });
    await page.screenshot({ path: path.join(output, "06-playing.png") });
    await page.keyboard.press("Escape");
    await page.locator('canvas[data-state="paused"]').waitFor();
    await page.waitForFunction(() => window.audioRms() < 0.00001, { }, { timeout: 3000 });
    await page.screenshot({ path: path.join(output, "02-paused.png") });
    const paused = await page.screenshot();
    await page.waitForTimeout(350);
    assert(paused.equals(await page.screenshot()), "Paused game must remain visually frozen");
    await page.keyboard.press("Escape");
    // With no steering the snake must eventually hit the right wall.
    await page.locator('canvas[data-state="over"]').waitFor({ timeout: 12000 });
    await page.screenshot({ path: path.join(output, "03-game-over.png") });
    // Sound control is rendered on the Godot canvas, in the lower-left footer.
    await page.mouse.click(105, 865);
    await page.waitForFunction(() => window.audioRms() < 0.00001, { }, { timeout: 3000 });
    await page.mouse.click(105, 865);
    await page.keyboard.press("d");
    await page.screenshot({ path: path.join(output, "09-debug-collision.png") });
    await page.keyboard.press("d");
    await page.keyboard.press("r");
    await page.locator('canvas[data-state="playing"][data-score="0"]').waitFor();
    await page.keyboard.down("ArrowRight");
    await page.waitForTimeout(500);
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
    await page.setViewportSize({ width: 1727, height: 831 });
    const wideLayout = await page.evaluate(() => {
      const element = document.querySelector("canvas");
      const canvas = element.getBoundingClientRect();
      return {
        canvas: {
          left: canvas.left,
          right: canvas.right,
          width: canvas.width,
          height: canvas.height,
          bufferWidth: element.width,
          bufferHeight: element.height,
        },
        viewport: { width: innerWidth, height: innerHeight },
      };
    });
    assert.deepEqual(
      { width: wideLayout.canvas.width, height: wideLayout.canvas.height },
      wideLayout.viewport,
      "Adaptive canvas must cover the browser viewport",
    );
    await page.screenshot({ path: path.join(output, "10-ultrawide.png") });
    const hiDpiPage = await browser.newPage({
      viewport: { width: 1727, height: 831 },
      deviceScaleFactor: 2,
    });
    await hiDpiPage.goto(process.env.GAME_URL || "http://127.0.0.1:8060");
    await hiDpiPage.locator("#status").waitFor({ state: "hidden", timeout: 30000 });
    const hiDpi = await hiDpiPage.evaluate(() => {
      const canvas = document.querySelector("canvas");
      return {
        cssWidth: canvas.clientWidth,
        cssHeight: canvas.clientHeight,
        bufferWidth: canvas.width,
        bufferHeight: canvas.height,
        dpr: devicePixelRatio,
      };
    });
    assert.equal(hiDpi.bufferWidth, hiDpi.cssWidth * hiDpi.dpr);
    assert.equal(hiDpi.bufferHeight, hiDpi.cssHeight * hiDpi.dpr);
    await hiDpiPage.close();
    assert.equal(errors.length, 0, errors.join("\n"));
    fs.writeFileSync(
      path.join(output, "browser-results.json"),
      JSON.stringify({ errors, layout, wideLayout, hiDpi, screenshots: 9 }, null, 2),
    );
    console.log("Browser smoke passed: gameplay, resize, audible effects, pause and mute; no console errors.");
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
