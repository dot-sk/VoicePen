# Evidence

- The installed 1.12.0 app enables both automatic checks and SUAutomaticallyUpdate. There are no explicit stored automatic-check/download preference overrides in the inspected production preference file.
- The current signed feed also advertises 1.12.0. This computer therefore cannot currently demonstrate an offer for a newer production version.
- System logs contain a connection to the configured appcast endpoint. A last-check timestamp or connection does not prove successful update discovery, archive verification or prompt presentation.
- Sparkle's official configuration documentation says SUAutomaticallyUpdate enables silent background installation; the default check interval is one day, and the default impatient reminder interval is one week. https://sparkle-project.org/documentation/customization/
- Change the defaults to hourly checks and SUAutomaticallyUpdate=false. Keep the existing standard driver and honor explicit Sparkle preferences.

# Verification

- `make test`: 755 tests in 84 suites passed, including bundled updater configuration assertions.
- Actual visible automatic prompting from an older installed app to a newer signed release remains unverified. No production preference changes, app replacement or release publishing were performed.
- `make build CONFIGURATION=Release DERIVED_DATA="$PWD/.local/nemotron-migration-build"`: BUILD SUCCEEDED. Built plist contains SUEnableAutomaticChecks=true, SUAutomaticallyUpdate=false and SUScheduledCheckInterval=3600.
- `openspec validate offer-automatic-update-prompts --strict --no-interactive` and `git diff --check`: passed.
