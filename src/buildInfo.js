// The build stamp scripts/build.mjs writes into the bundle: package version,
// short commit and build time (UTC). Shown on the title screen and the HUD so
// a player can tell which build they are on.

/* global __BUILD__ */
export const BUILD = typeof __BUILD__ !== 'undefined' ? __BUILD__ : { version: '0.0.0', commit: 'dev', date: '' };

// "v0.1.0 · 3f9c2ab · 2026-10-19 08:40 UTC"
export const BUILD_LABEL = [`v${BUILD.version}`, BUILD.commit, BUILD.date].filter(Boolean).join(' · ');
