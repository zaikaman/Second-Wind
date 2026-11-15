<!--
Sync Impact Report
Version change: unratified scaffold → 1.0.0
Amendment 2026-11-15: 1.0.0 → 1.1.0 — added the single-branch (`main`) workflow rule.
Modified principles: template placeholders → I. Clear, Focused Code; II. Secure Contract Boundaries; III. Tests Define Expected Behavior; IV. Verify Cross-Chain Integration; V. Maintainability and Simplicity
Added sections: Engineering Constraints; Development and Quality Workflow
Removed sections: none
Follow-up TODOs: Confirm the original ratification date.
-->
# Second Wind Constitution

## Core Principles

### I. Clear, Focused Code
Production code MUST use descriptive names, explicit control flow, and small cohesive units. Each contract, module, and function MUST have a clear responsibility. Shared behavior MUST be factored into reusable code when that reduces duplication without obscuring control flow. Rationale: readable code makes financial behavior easier to review and change safely.

### II. Secure Contract Boundaries
Every externally callable contract function MUST validate authorization, inputs, and relevant state before changing funds or policy state. Cross-chain callbacks MUST authenticate the configured proxy and recorded guardian, reject duplicate `runId` values, and enforce destination-side limits. A destination contract MUST independently verify critical on-chain facts instead of trusting values supplied by another chain. Rationale: each chain boundary is an untrusted input boundary.

### III. Tests Define Expected Behavior
Every behavior change MUST include or update automated tests that demonstrate its expected result. Tests MUST cover successful behavior and relevant boundary conditions, including authorization failures, invalid inputs, replays, and accounting limits. Bug fixes MUST add a regression test when the failure can be reproduced. A change MUST NOT be considered complete if its relevant test suite fails.

### IV. Verify Cross-Chain Integration
Changes to event decoding, policy mirroring, callback dispatch, settlement, or claims MUST be checked across the affected chain boundaries. Integration coverage MUST verify that both callback branches use the same `runId`, that duplicate delivery cannot pay twice, and that a failure or delay on one branch does not falsely report the other as complete. Timing claims MUST be supported by measurements from the target test environment.

### V. Maintainability and Simplicity
Implementations MUST choose the simplest design that meets the stated requirements and MUST document non-obvious financial or cross-chain decisions near the relevant code. New dependencies, abstractions, and configuration MUST have a concrete need and an owner. Public interfaces and storage layouts MUST change only with documented compatibility and migration implications. Rationale: avoid making future security review and protocol upgrades harder than necessary.

## Engineering Constraints

- Contracts MUST follow checks-effects-interactions where applicable and guard external calls against reentrancy.
- Financial calculations MUST use explicit units, bounded inputs, and documented rounding behavior. Tests MUST cover relevant rounding and cap boundaries.
- Secrets MUST NOT be committed. Test and demo configuration MUST make chain IDs, addresses, and callback authorities explicit.
- Oracle assumptions and demo-only components MUST be identified in code or project documentation; production safety MUST NOT be implied by demo harnesses.

## Development and Quality Workflow

- All work happens on the `main` branch. Agents, scripts, and hooks MUST NOT create, switch, rename, or delete git branches. A new feature gets a directory under `specs/`, not a new branch.
- Before implementation, identify the user-visible behavior, affected contracts or modules, and the tests that will prove the behavior.
- Before review or merge, run the relevant automated tests and build checks, and report the commands and outcomes. If a check cannot run, document the reason and remaining uncertainty.
- Reviews MUST check correctness, authorization, failure handling, duplicate processing, and maintainability for the changed paths. Material deviations from these principles MUST be explained in the change description and resolved or explicitly accepted by project maintainers.
- Documentation and examples MUST be updated when interfaces, assumptions, operational steps, or user-visible behavior change.

## Governance

This constitution governs project implementation and review. Amendments MUST update this document, record the rationale, and increment the version according to semantic versioning: MAJOR for incompatible governance changes, MINOR for new or materially expanded principles or requirements, and PATCH for clarifications that do not change obligations. Changes to the constitution MUST be reviewed for conflicts with existing project guidance and identify any follow-up updates required. Every change review MUST assess compliance with these principles; any exception MUST state its scope, rationale, and remediation plan.

**Version**: 1.1.0 | **Ratified**: TODO(RATIFICATION_DATE): confirm original adoption date | **Last Amended**: 2026-11-15
