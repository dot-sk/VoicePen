## Decision

Use Sparkle's supported Info.plist defaults: automatic checks enabled,
SUAutomaticallyUpdate disabled and SUScheduledCheckInterval set to 3600 seconds.
The hourly schedule respects Sparkle's minimum and avoids custom polling or a
second updater. Do not mutate updater preferences on launch: Sparkle must retain
explicit user choices. The standard user driver still decides when it can show
a scheduled alert without interrupting the user.

## Verification

Assert the bundled configuration, feed URL and signing key in the existing
configuration test; run make test and build the app. Inspect the built plist.
A real older installed build receiving a newer signed release is a separate
end-to-end verification, not established by configuration or last-check dates.
No ADR is needed for this reversible configuration adjustment.
