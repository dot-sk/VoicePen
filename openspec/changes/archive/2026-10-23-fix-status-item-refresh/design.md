## Context

The native status item derives a snapshot from several `@Published` properties. Their synchronous notifications arrive before the underlying property is stored, so reading the controller inside the notification can retain the preceding state.

## Decisions

- Deliver the existing subscriptions through `DispatchQueue.main` before rebuilding the snapshot. This preserves one snapshot source and avoids manually combining incoming values with other properties or changing dictation lifecycle ordering.
- Keep menu rebuilding on menu open. State notifications continue to update only the cached snapshot and status item icon.
- Make the status item controller and its read-only snapshot internal for hosted regression coverage. Test the real subscription without creating a visible status item, starting capture, or invoking menu-open callbacks.
- Compare the observed snapshot with snapshots initialized from committed state. Wait for queued delivery with a continuation dispatched to the same main queue, without sleeps or polling.

## Risks / Trade-offs

- Refresh happens on the next main-queue turn. Rapid transitions can converge on the latest snapshot; the contract requires the current state rather than displaying every transient step.
- Hosted tests cover the common observer through app-state transitions. Existing unit tests cover dictation state cleanup and icon policy.
