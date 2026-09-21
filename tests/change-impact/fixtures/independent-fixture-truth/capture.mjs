import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const relevant = (name) => name.endsWith(".mjs") || name.endsWith("-registry.json");

async function walk(root, relative = "") {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true });
  const paths = [];
  for (const entry of entries) {
    const next = path.join(relative, entry.name);
    if (entry.isDirectory()) paths.push(...await walk(root, next));
    else if (relevant(entry.name)) paths.push(next);
  }
  return paths.sort();
}

export async function capture(root) {
  const files = await walk(root);
  const entries = await Promise.all(files.map(async (file) => {
    const bytes = await readFile(path.join(root, file));
    return { file, sha256: createHash("sha256").update(bytes).digest("hex") };
  }));
  const content = entries.map((entry) => `${entry.file}:${entry.sha256}`).join("\n");
  return { identity_kind: "content-sha256/no-git", files: entries, universe_sha256: createHash("sha256").update(content).digest("hex") };
}
