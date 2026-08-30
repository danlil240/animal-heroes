# Archived Plans

Plans parked here are blocked on prerequisites an agent cannot provide:
real SM-T220 tablets, a configured release keystore, supervised child
usability sessions, or a native Hebrew reviewer.

## 2026-08-29-local-release-deployment.md

Automated portion is complete and merged: the stdlib-only deploy service,
catalog, pipeline, dashboard routes, TLS identity, device probing, rollback,
evidence gates, and 226 passing unit tests. Remaining work is the deliberate
"known gap" (LAN API socket binding + real challenge verifier, see
`AGENTS.md`) and physical acceptance on two real tablets (task 13 step 8).
Archived because physical acceptance requires real hardware and a configured
keystore that are not available in this environment.

## 2026-08-29-release-candidate-stabilization.md

Tasks 1-3 (multi-process LAN gate, release metadata, Android build/permission
validation) are complete and merged. Tasks 4-6 require two SM-T220 tablets,
endurance/performance runs, supervised child-usability sessions, a native
Hebrew copy review, and a signed release keystore. The release checklist
records these as PENDING DEVICE/USABILITY/PROVENANCE checks. Archived because
no agent can perform on-device or supervised-human gates.
