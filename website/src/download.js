import "./style.css";

import {
  channelLabel,
  fetchReleaseManifest,
  primaryMacDownloadUrl,
  zipFallbackUrl
} from "./release.js";

document.addEventListener("DOMContentLoaded", async () => {
  try {
    const manifest = await fetchReleaseManifest();
    hydrateDownloadPage(manifest);
  } catch (error) {
    console.error(error);
    renderUnavailableState();
  }
});

function hydrateDownloadPage(manifest) {
  const primaryUrl = primaryMacDownloadUrl(manifest);
  const zipUrl = zipFallbackUrl(manifest);
  const releaseNotesUrl = manifest?.macos?.releaseNotesUrl || "/support";
  const version = manifest?.version || "Unavailable";
  const channel = channelLabel(manifest?.channel);
  const minVersion = manifest?.macos?.minVersion || "macOS 13.0";
  const status = manifest?.macos?.status || "planned";

  setText("[data-release-version]", version);
  setText("[data-release-channel]", channel);
  setText("[data-macos-min-version]", minVersion);

  setLink("[data-primary-download]", primaryUrl);
  setLink("[data-zip-download]", zipUrl);
  setLink("[data-release-notes-link]", releaseNotesUrl);

  const statusNode = document.querySelector("[data-download-status]");
  if (!statusNode) {
    return;
  }

  if (manifest?.macos?.dmgUrl || manifest?.macos?.zipUrl) {
    statusNode.textContent = `Version ${version} on the ${channel.toLowerCase()} channel is available. Redirecting to the primary macOS download now.`;
    window.setTimeout(() => {
      window.location.assign(primaryUrl);
    }, 1200);
    return;
  }

  statusNode.textContent = `The current channel is ${status}. Public DMG and ZIP links have not been published yet, so this page is keeping you on the release notes and support path instead of sending you to a dead download.`;
}

function renderUnavailableState() {
  setText("[data-release-version]", "Unavailable");
  setText("[data-release-channel]", "OFFLINE");
  setText("[data-macos-min-version]", "macOS 13.0");

  const statusNode = document.querySelector("[data-download-status]");
  if (statusNode) {
    statusNode.textContent = "The release manifest could not be loaded. Use the release notes link while the site configuration is being restored.";
  }
}

function setText(selector, value) {
  document.querySelectorAll(selector).forEach((node) => {
    node.textContent = value;
  });
}

function setLink(selector, href) {
  document.querySelectorAll(selector).forEach((node) => {
    node.setAttribute("href", href);
  });
}
