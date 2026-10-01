## Why

The v1.11.0 release promoted its CI archive successfully but failed to generate the appcast because the fresh release runner had no Sparkle signing tool. Promoting a candidate does not resolve build dependencies.

## What Changes

- Prepare update-signing tools before generating the appcast for a promoted release candidate.
- Keep the validated archive unchanged until the existing signing and promotion steps.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `github-release-auto-updates`: Prepare tools required to sign the update feed even when no release compilation occurs.

## Impact

Release workflow and automated workflow-configuration coverage. No app runtime behavior changes.
