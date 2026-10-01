## ADDED Requirements

### Requirement: Promoted releases prepare update signing tools

Release publishing SHALL prepare the tools needed to sign update metadata independently of app compilation when promoting a validated candidate on a fresh runner.

#### Scenario: Candidate is promoted on a fresh release runner

- **WHEN** a validated release candidate is promoted on a runner without build dependencies
- **THEN** publication prepares update-signing tools before generating the signed appcast without recompiling the candidate
