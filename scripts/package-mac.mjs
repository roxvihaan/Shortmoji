import { chmod, copyFile, cp, mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const root = process.cwd();
const { version } = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
const developerDir = process.env.DEVELOPER_DIR || "/Applications/Xcode.app/Contents/Developer";
const buildEnvironment = {
  ...process.env,
  DEVELOPER_DIR: developerDir,
  SWIFTPM_MODULECACHE_OVERRIDE: "/private/tmp/shortmoji-spm-cache",
  CLANG_MODULE_CACHE_PATH: "/private/tmp/shortmoji-clang-cache",
};

const build = spawnSync(
  "xcrun",
  ["swift", "build", "-c", "release", "--disable-sandbox"],
  { cwd: root, env: buildEnvironment, stdio: "inherit" },
);
if (build.status !== 0) process.exit(build.status ?? 1);

const appPath = join(root, "release", "Shortmoji.app");
const contentsPath = join(appPath, "Contents");
const executablePath = join(contentsPath, "MacOS", "Shortmoji");
const resourcesPath = join(contentsPath, "Resources");
const buildPath = join(root, ".build", "arm64-apple-macosx", "release");

await rm(appPath, { recursive: true, force: true });
await mkdir(join(contentsPath, "MacOS"), { recursive: true });
await mkdir(resourcesPath, { recursive: true });
await copyFile(join(buildPath, "Shortmoji"), executablePath);
await chmod(executablePath, 0o755);
await cp(
  join(buildPath, "Shortmoji_ShortmojiCore.bundle"),
  join(resourcesPath, "Shortmoji_ShortmojiCore.bundle"),
  { recursive: true },
);

const infoPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Shortmoji</string>
  <key>CFBundleExecutable</key>
  <string>Shortmoji</string>
  <key>CFBundleIdentifier</key>
  <string>com.shortmoji.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Shortmoji</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAccessibilityUsageDescription</key>
  <string>Shortmoji uses Accessibility access to recognize emoji shortcodes and insert emoji in the app where you are typing.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`;
await writeFile(join(contentsPath, "Info.plist"), infoPlist);
await writeFile(join(contentsPath, "PkgInfo"), "APPL????");

const signIdentity = process.env.SHORTMOJI_SIGN_IDENTITY || "-";
const signArguments = ["--force", "--deep", "--sign", signIdentity];
if (signIdentity === "-") {
  signArguments.push(
    "--identifier",
    "com.shortmoji.app",
    "--requirements",
    '=designated => identifier "com.shortmoji.app"',
  );
}
signArguments.push(appPath);

const sign = spawnSync("codesign", signArguments, { stdio: "inherit" });
if (sign.status !== 0) process.exit(sign.status ?? 1);

const verify = spawnSync("codesign", ["--verify", "--deep", "--strict", appPath], {
  stdio: "inherit",
});
if (verify.status !== 0) process.exit(verify.status ?? 1);

console.log(`Created native macOS app: ${appPath}`);
