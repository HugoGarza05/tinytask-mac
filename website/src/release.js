const manifestUrl = "/release-manifest.json";

export async function fetchReleaseManifest() {
  const response = await fetch(manifestUrl, {
    headers: {
      Accept: "application/json"
    }
  });

  if (!response.ok) {
    throw new Error(`Failed to load release manifest: ${response.status}`);
  }

  return response.json();
}

export function primaryMacDownloadUrl(manifest) {
  return manifest?.macos?.dmgUrl || manifest?.macos?.zipUrl || manifest?.macos?.releaseNotesUrl || "/support";
}

export function zipFallbackUrl(manifest) {
  return manifest?.macos?.zipUrl || manifest?.macos?.releaseNotesUrl || "/support";
}

export function channelLabel(channel) {
  if (!channel) {
    return "unknown";
  }

  return channel.toUpperCase();
}

export function platformSummary(manifest) {
  const windows = capitalizeStatus(manifest?.windows?.status);
  const linux = capitalizeStatus(manifest?.linux?.status);
  return `macOS now, Windows ${windows.toLowerCase()}, Linux ${linux.toLowerCase()}`;
}

export function capitalizeStatus(value) {
  if (!value) {
    return "Unknown";
  }

  return value.charAt(0).toUpperCase() + value.slice(1);
}
