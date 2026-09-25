import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
const [source, supportedFile] = process.argv.slice(2);
if (!source || !supportedFile) throw new Error("Usage: node scripts/import-unicode.mjs emoji-test.txt supported.json");
const destination = resolve(import.meta.dirname, "../Sources/ShortmojiCore/Resources/emoji.json");
const old = JSON.parse(await readFile(destination, "utf8"));
const key = value => value.replaceAll("\uFE0F", "");
const previous = new Map(old.map(entry => [key(entry.emoji), entry]));
const supported = new Set(JSON.parse(await readFile(supportedFile, "utf8")));
const normalize = value => value.normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
  .toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
const sourceText = await readFile(source, "utf8");
const records = [];
let category = "";
for (const line of sourceText.split("\n")) {
  if (line.startsWith("# group: ")) category = line.slice(9);
  const match = line.match(/^([0-9A-F ]+)\s*; (fully-qualified|component)\s*# \S+ E[\d.]+ (.+)$/);
  if (!match) continue;
  const emoji = String.fromCodePoint(...match[1].trim().split(/\s+/).map(value => parseInt(value, 16)));
  if (!supported.has(emoji)) continue;
  records.push({ emoji, description: match[3], category });
}
const names = new Set();
const entries = records.map(record => {
  const existing = previous.get(key(record.emoji));
  const unicodeName = normalize(record.description);
  const baseEmoji = record.emoji.replace(/[\u{1F3FB}-\u{1F3FF}]/gu, "");
  const base = previous.get(key(baseEmoji));
  const tones = record.description.match(/(?:medium-light|medium-dark|light|medium|dark) skin tone/g) ?? [];
  const name = existing?.name ?? (base && tones.length
    ? `${base.name}_${tones.map(normalize).join("_")}` : unicodeName);
  if (names.has(name)) throw new Error(`Duplicate shortcode: ${name}`);
  names.add(name);
  return { emoji: record.emoji, name,
    aliases: [...new Set([...(existing?.aliases ?? []), unicodeName].filter(alias => alias !== name))],
    keywords: existing?.keywords ?? [record.description], category: record.category };
});
if (entries.length !== supported.size) throw new Error("Some supported emoji were not imported");
await writeFile(destination, JSON.stringify(entries, null, 2) + "\n");
console.log(`Imported all ${entries.length} supported Unicode emoji, including variants.`);
