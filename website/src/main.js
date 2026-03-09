import "./style.css";

import {
  capitalizeStatus,
  channelLabel,
  fetchReleaseManifest,
  platformSummary
} from "./release.js";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

document.addEventListener("DOMContentLoaded", async () => {
  setupRevealAnimations();
  setupTiltCards();
  setupParallax();

  try {
    const manifest = await fetchReleaseManifest();
    hydrateManifestFields(manifest);
  } catch (error) {
    console.error(error);
    hydrateFallbackState();
  }
});

function hydrateManifestFields(manifest) {
  setText("[data-release-version]", manifest.version);
  setText("[data-release-channel]", channelLabel(manifest.channel));
  setText("[data-platform-summary]", platformSummary(manifest));

  const notesUrl = manifest?.macos?.releaseNotesUrl || "/support";
  const checksumUrl = manifest?.macos?.checksumUrl || notesUrl;

  setLinks("[data-release-notes-link]", notesUrl);
  setLinks("[data-checksum-link]", checksumUrl);

  const statusNodes = document.querySelectorAll("[data-macos-status]");
  statusNodes.forEach((node) => {
    node.textContent = capitalizeStatus(manifest?.macos?.status);
  });
}

function hydrateFallbackState() {
  setText("[data-release-version]", "Unavailable");
  setText("[data-release-channel]", "OFFLINE");
  setText("[data-platform-summary]", "macOS status unavailable");
}

function setText(selector, value) {
  document.querySelectorAll(selector).forEach((node) => {
    node.textContent = value;
  });
}

function setLinks(selector, href) {
  document.querySelectorAll(selector).forEach((node) => {
    node.setAttribute("href", href);
  });
}

function setupRevealAnimations() {
  const revealItems = document.querySelectorAll("[data-reveal]");
  if (reducedMotion.matches || !("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    {
      rootMargin: "0px 0px -8% 0px",
      threshold: 0.15
    }
  );

  revealItems.forEach((item) => observer.observe(item));
}

function setupTiltCards() {
  if (reducedMotion.matches) {
    return;
  }

  document.querySelectorAll(".tilt-card").forEach((card) => {
    card.addEventListener("pointermove", (event) => {
      const rect = card.getBoundingClientRect();
      const x = (event.clientX - rect.left) / rect.width;
      const y = (event.clientY - rect.top) / rect.height;
      const tiltX = (0.5 - y) * 10;
      const tiltY = (x - 0.5) * 12;

      card.style.setProperty("--tilt-x", `${tiltX.toFixed(2)}deg`);
      card.style.setProperty("--tilt-y", `${tiltY.toFixed(2)}deg`);
    });

    card.addEventListener("pointerleave", () => {
      card.style.removeProperty("--tilt-x");
      card.style.removeProperty("--tilt-y");
    });
  });
}

function setupParallax() {
  if (reducedMotion.matches) {
    document.documentElement.style.setProperty("--parallax-offset", "0px");
    return;
  }

  const onScroll = () => {
    const offset = Math.min(window.scrollY * 0.12, 120);
    document.documentElement.style.setProperty("--parallax-offset", `${offset}px`);
  };

  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}
