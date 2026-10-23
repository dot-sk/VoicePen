## 1. Contract and regression coverage

- [x] 1.1 Specify automatic status refresh from committed state, including readiness, warning/meeting states, and rapid transitions.
- [x] 1.2 Add hosted subscription tests for all three delta scenarios with deterministic main-queue synchronization and confirm the regression before the scheduling fix.

## 2. Implementation

- [x] 2.1 Deliver status observation on the main queue after the published property is stored, preserving menu and icon policy.

## 3. Verification

- [x] 3.1 Run strict OpenSpec validation and `make test`.
- [x] 3.2 Run `make build` and `make integration-test`.
