import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

// Merge a downloaded github/gemoji db/emoji.json into the bundled catalog.
// Existing names and curated search keywords stay stable across imports.
const source = process.argv[2];
if (!source) throw new Error("Usage: node scripts/import-emoji.mjs /path/to/gemoji.json");
const destination = resolve(import.meta.dirname, "../Sources/ShortmojiCore/Resources/emoji.json");
const entries = JSON.parse(await readFile(destination, "utf8"));
const upstream = JSON.parse(await readFile(source, "utf8"));
const key = value => value.replaceAll("\uFE0F", "");
const byEmoji = new Map(entries.map(entry => [key(entry.emoji), entry]));
const occupied = new Set(entries.flatMap(entry => [entry.name, ...entry.aliases]));
for (const item of upstream) {
  if (!item.emoji || !item.aliases?.length) continue;
  const existing = byEmoji.get(key(item.emoji));
  const available = item.aliases.filter(alias => !occupied.has(alias));
  if (existing) {
    existing.aliases.push(...available);
  } else if (available.length) {
    const entry = { emoji: item.emoji, name: available[0], aliases: available.slice(1),
      keywords: [...new Set([...(item.tags ?? []), item.description])] };
    entries.push(entry);
    byEmoji.set(key(item.emoji), entry);
  }
  available.forEach(alias => occupied.add(alias));
}
await writeFile(destination, JSON.stringify(entries, null, 2) + "\n");
console.log(`Bundled ${entries.length} emoji (${upstream.length} upstream records).`);
