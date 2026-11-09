// Exercise the exported HTML/JS/WASM/PCK, not project source files.
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const baseUrl = process.env.BASE_URL ?? "http://127.0.0.1:8765/";
const outputDir = process.env.SCREENSHOT_DIR ?? "browser-smoke-output";
const errors = [];
let browser;
let page;

try {
  await mkdir(outputDir, { recursive: true });
  browser = await chromium.launch({
    headless: true,
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  page = await context.newPage();
  page.on("pageerror", (error) => errors.push("JavaScript: " + error.message));
  page.on("crash", () => errors.push("Chromium page crashed"));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push("Console: " + message.text());
  });
  page.on("response", (response) => {
    if (response.status() >= 400 && response.url().startsWith(baseUrl)) {
      errors.push("HTTP " + response.status() + ": " + response.url());
    }
  });
  page.on("requestfailed", (request) => {
    if (request.url().startsWith(baseUrl)) {
      errors.push("Request: " + request.url() + " (" + (request.failure()?.errorText ?? "unknown") + ")");
    }
  });

  await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.waitForFunction(() => {
    const canvas = document.getElementById("canvas");
    if (!(canvas instanceof HTMLCanvasElement) || canvas.width < 320 || canvas.height < 180) return false;
    const overlay = document.getElementById("status");
    if (!overlay) return true;
    const style = getComputedStyle(overlay);
    return style.display === "none" || style.visibility === "hidden"
      || style.opacity === "0" || overlay.hidden;
  }, null, { timeout: 120_000 });

  // Splash disappearance alone is insufficient: Godot 4 Web requires WebGL 2.
  const canvas = page.locator("#canvas");
  await page.waitForTimeout(1_500);
  const webgl2 = await canvas.evaluate((element) => Boolean(element.getContext("webgl2")));
  assert.ok(webgl2, "Godot exported canvas has no WebGL 2 context");

  // Focus the game and exercise real keyboard input without changing gameplay.
  await canvas.click({ position: { x: 100, y: 100 } });
  await page.keyboard.down("w");
  await page.waitForTimeout(600);
  await page.keyboard.up("w");
  await page.keyboard.press("Space");
  await page.keyboard.press("q");
  await page.waitForTimeout(500);

  assert.deepEqual(errors, [], "Browser errors during game startup/input");
  console.log("PASS: exported Godot game initialized in Chromium/WebGL 2; input generated no browser errors");
} catch (error) {
  console.error("FAIL: browser smoke-test: " + (error.stack ?? error));
  process.exitCode = 1;
} finally {
  if (page) {
    const notice = await page.locator("#status-notice").textContent({ timeout: 2_000 }).catch(() => "");
    if (notice?.trim()) errors.push("Godot status: " + notice.trim());
    await page.screenshot({ path: path.join(outputDir, "screen.png"), timeout: 10_000 }).catch(() => {});
  }
  await writeFile(path.join(outputDir, "diagnostics.json"), JSON.stringify({ baseUrl, errors }, null, 2));
  await browser?.close();
}
