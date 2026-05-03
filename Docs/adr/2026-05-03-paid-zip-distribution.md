---
id: ADR-0003
status: accepted
date: 2026-05-03
---

# Paid Zip Distribution

## Context

VoicePen may later be sold as a simple paid macOS download: a customer pays once,
receives a zip archive, installs the app, and continues receiving app updates.

The app already has a direct-distribution update path through Sparkle, GitHub
Releases, and a public appcast. Adding in-app accounts, license keys, or gated
update feeds would increase product and support complexity before there is a
clear need to restrict updates after purchase.

## Decision

Keep the first paid distribution model as a direct paid zip download outside the
Mac App Store.

Do not add in-app license enforcement for the first paid version. A customer who
buys the app once can continue receiving updates through the public Sparkle feed.
Treat the public update archive as an acceptable honor-system tradeoff for the
initial paid product.

Before selling, release builds should be signed with Developer ID, notarized,
stapled, and packaged as a normal macOS zip rather than an unsigned Friends &
Family archive.

## Consequences

The paid MVP stays simple: no account system, no license activation flow, no
gated appcast, and no payment-provider SDK inside VoicePen.

The update feed and archive URLs are not access-controlled, so a determined
person could share or download update archives without buying. If that becomes a
real business problem, VoicePen can later add license activation or gated
downloads as a separate decision.

The app should avoid hard-coded "free" product copy so the same codebase can be
used for paid builds without confusing customers.

## Links

- [SPEC-006 GitHub Release Auto Updates](../../Specs/2026-05-02-github-release-auto-updates.md)
- `VoicePen/App/SettingsViews.swift`
