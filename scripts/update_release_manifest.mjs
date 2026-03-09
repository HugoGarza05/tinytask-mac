import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const manifestPath = resolve(process.cwd(), "website/public/release-manifest.json");

const options = parseArgs(process.argv.slice(2));
const current = JSON.parse(await readFile(manifestPath, "utf8"));

const next = {
  ...current,
  version: options.version ?? current.version,
  channel: options.channel ?? current.channel,
  publishedAt: options.publishedAt ?? new Date().toISOString(),
  macos: {
    ...current.macos,
    status: options.macosStatus ?? current.macos.status,
    minVersion: options.minVersion ?? current.macos.minVersion,
    dmgUrl: options.dmgUrl ?? current.macos.dmgUrl,
    zipUrl: options.zipUrl ?? current.macos.zipUrl,
    checksumUrl: options.checksumUrl ?? current.macos.checksumUrl,
    releaseNotesUrl: options.releaseNotesUrl ?? current.macos.releaseNotesUrl
  },
  windows: {
    ...current.windows,
    status: options.windowsStatus ?? current.windows.status
  },
  linux: {
    ...current.linux,
    status: options.linuxStatus ?? current.linux.status
  }
};

await writeFile(manifestPath, `${JSON.stringify(next, null, 2)}\n`);
console.log(`Updated ${manifestPath}`);

function parseArgs(argv) {
  const parsed = {};

  for (let index = 0; index < argv.length; index += 1) {
    const part = argv[index];
    if (!part.startsWith("--")) {
      continue;
    }

    const key = part.slice(2);
    const value = argv[index + 1];
    parsed[key] = value;
    index += 1;
  }

  return parsed;
}
