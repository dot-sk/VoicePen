## Why

VoicePen enables silent automatic installation by default. Users asked to see an
update offer, but Sparkle may stage/install silently and defer reminders. A last
check timestamp establishes an attempted check, not successful discovery or a
visible prompt.

## What Changes

- Keep automatic checks enabled, with an hourly default schedule.
- Default to Sparkle's visible update offer and user-approved installation instead of silent automatic downloading/installing.
- Honor any explicit update preferences already stored by Sparkle.
- Keep the signed feed, manual command and release publishing unchanged.

## Capabilities

### Modified Capabilities

- `github-release-auto-updates`: default update discovery and presentation policy.

## Impact

Bundled Info.plist, configuration tests and the main update specification.
