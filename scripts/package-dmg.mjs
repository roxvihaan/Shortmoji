import { cp, mkdtemp, symlink, writeFile, rm, access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { readFile } from "node:fs/promises";

const root = resolve(import.meta.dirname, "..");
const { version } = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
const output = join(root, "release", `Shortmoji-${version}-arm64.dmg`);
let exists = false;
try { await access(output); exists = true; } catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (exists) throw new Error(`Refusing to overwrite ${output}. Bump the version for a new release.`);
const stage = await mkdtemp(join(tmpdir(), "shortmoji-dmg-"));
try {
  await cp(join(root, "release", "Shortmoji.app"), join(stage, "Shortmoji.app"), { recursive: true });
  await symlink("/Applications", join(stage, "Applications"));
  await writeFile(join(stage, "Install Shortmoji.txt"),
    "Shortmoji — emoji at your fingertips\n\nDrag Shortmoji.app to Applications, then open it.\nAllow Accessibility access when prompted to enable shortcode replacement.\nType :sku for suggestions or :skull: to insert 💀.\n\nRequires macOS 14 or later and Apple Silicon.\nThis release is locally signed, not Apple-notarized. macOS may block its first launch.\nOnly if you trust this download, use System Settings > Privacy & Security > Open Anyway.\n");
  const result = spawnSync("hdiutil", ["create", "-volname", "Shortmoji", "-srcfolder", stage,
    "-format", "UDZO", "-fs", "HFS+", output], { stdio: "inherit" });
  if (result.status !== 0) throw new Error("DMG creation failed");
  const verify = spawnSync("hdiutil", ["verify", output], { stdio: "inherit" });
  if (verify.status !== 0) throw new Error("DMG verification failed");
  console.log(`Created ${output}`);
} finally {
  await rm(stage, { recursive: true, force: true });
}
