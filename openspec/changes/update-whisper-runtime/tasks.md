## 1. Update dependency

- [x] 1.1 Pin official v1.9.5/b5454 XCFramework and verified checksum, document provenance, and update execution diagnostics.

## 2. Automated compatibility coverage

- [x] 2.1 Extend the opt-in native test to check Q5/Q8 reuse with and without legacy companions, runtime identity, word confidence, and timestamped segments.
- [x] 2.2 Run native Whisper and GigaAM tests together in the same process; run make test and make build; inspect the bundled runtime and strictly validate the change.

## 3. Record results

- [x] 3.1 Record exact checks and limitations, and sync the delta into main specs without archiving or committing.
