import { readFile, readdir } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const layout = JSON.parse(await readFile(resolve(root, "layout.json"), "utf8"));
const positions = new Set(layout.map(item => item.position));
const expectedPositions = new Set(Array.from({ length: 4 }, (_, row) => Array.from({ length: 8 }, (_, column) => `${column},${row}`)).flat());
const buttonFiles = (await readdir(resolve(root, "buttons"))).filter(name => name.endsWith(".png"));
const errors = [];

if (layout.length !== 32) errors.push(`layout.json has ${layout.length} actions instead of 32`);
if (positions.size !== 32) errors.push("layout.json contains duplicate positions");
for (const position of expectedPositions) if (!positions.has(position)) errors.push(`layout.json is missing position ${position}`);
for (const item of layout) {
  const expectedImage = `${item.position.replace(",", "-")}.png`;
  if (!buttonFiles.includes(expectedImage)) errors.push(`missing button image ${expectedImage}`);
  if (!item.label || !item.type || !item.category) errors.push(`incomplete action at ${item.position}`);
  if (item.type === "text" && !item.text) errors.push(`text action at ${item.position} has no text`);
  if (item.type === "hotkey" && !item.key) errors.push(`hotkey action at ${item.position} has no key`);
}

const textFiles = ["README.md", "SECURITY.md", "SUPPORT.md", "CHANGELOG.md", "layout.json", "installer/install.ps1", "Install Codex Control Page.cmd"];
const privatePatterns = [
  /C:\\Users\\/i,
  /192\.168\.86\./,
  /65116AA0|12C92AF6/i,
  /BEGIN [A-Z ]*PRIVATE KEY/,
];
for (const file of textFiles) {
  const content = await readFile(resolve(root, file), "utf8");
  for (const pattern of privatePatterns) if (pattern.test(content)) errors.push(`${file} contains private or machine-specific data`);
}

if (buttonFiles.length !== 32) errors.push(`buttons contains ${buttonFiles.length} PNG files instead of 32`);
if (errors.length) {
  console.error(errors.map(error => `- ${error}`).join("\n"));
  process.exit(1);
}
console.log("Validated the 32-key layout, assets, installer, and privacy rules.");
