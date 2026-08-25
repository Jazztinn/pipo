import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const websiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(websiteRoot, "..");
const source = resolve(repoRoot, "app/Sources/PipoUI/Resources/MenuWeb");
const target = resolve(websiteRoot, "public/pipo-menu");
const files = ["index.html", "menu.css", "menu.js", "demo-fixture.json", "pipoclick.mp3"];
const hashFiles = [...files, "css/fontawesome.min.css", "webfonts/fa-regular-400.woff2", "webfonts/fa-solid-900.woff2"];

await rm(target, { recursive: true, force: true });
await mkdir(resolve(target, "css"), { recursive: true });
await mkdir(resolve(target, "webfonts"), { recursive: true });
for (const file of files) await cp(resolve(source, file), resolve(target, file));
await cp(resolve(source, "css/fontawesome.min.css"), resolve(target, "css/fontawesome.min.css"));
await cp(resolve(source, "webfonts"), resolve(target, "webfonts"), { recursive: true });

const hash = createHash("sha256");
for (const file of hashFiles) hash.update(await readFile(resolve(target, file)));
await writeFile(resolve(target, ".canonical-sha256"), `${hash.digest("hex")}\n`);
