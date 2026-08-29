# Animal Heroes Local Release Deployment Design

**Date:** 2026-08-29  
**Status:** Approved for implementation planning  
**Target:** This Ubuntu/GNOME workstation and two Samsung Galaxy Tab A7 Lite Wi-Fi tablets (`SM-T220`)

## Purpose

Animal Heroes needs a safe, simple way to build, sign, retain, select, and deploy release APKs from this PC over the private local network. A parent should be able to update both tablets from either the PC dashboard or one parent-gated button inside the game. The workflow must preserve Android signing continuity, keep the two tablets on compatible versions, and make failures recoverable without silently deleting save data.

The system is a development and household deployment tool, not a public app store. It is intentionally scoped to this Linux PC, this repository, the `org.danlil.animalheroes` package, and exactly two paired `SM-T220` tablets.

## Goals

- Provide a local browser dashboard that starts from an **Animal Heroes Deploy** desktop shortcut.
- Build and sign Android release APKs without storing signing secrets in Git, project files, logs, browser storage, or command arguments.
- Maintain an immutable local catalog of candidates and stable releases with source, version, signer, checksum, and validation evidence.
- Pair and manage exactly two tablets through Android Wireless Debugging and an application-level pairing step.
- Deploy the active APK to both tablets as one coordinated operation.
- Add a Hebrew, parent-gated in-game panel with installed/available version status and one **Update both tablets** action.
- Rebuild older source as a new higher-version release for safe rollback while preserving application data.
- Reject incompatible, unsigned, wrongly signed, wrongly permissioned, replayed, or partial operations.
- Retain auditable evidence for every build and deployment.

## Non-goals

- General-purpose Android device management.
- Google Play, public Internet, cloud storage, or remote deployment outside the private LAN.
- Windows or macOS support in the first version.
- Silent self-installation performed by the game.
- A separate updater APK.
- Arbitrary shell-command execution from the browser or tablet API.
- Automatic keystore creation, rotation, deletion, or backup.
- Automatic removal of published releases.
- Automatic save-data migration across an incompatible save schema.

## Constraints and Assumptions

- Both tablets are clean and do not contain production save data or a release-signed installation.
- The first release enrollment may therefore replace any debug installation without migration. The dashboard must still detect a signature conflict and obtain an explicit confirmation before uninstalling anything.
- Both tablets run Android 11 or later and support Android Wireless Debugging.
- This PC and both tablets are on the same trusted private network.
- The Android SDK, Godot 4.7.2, matching export templates, OpenJDK 17, Git, OpenSSL, `secret-tool`, and a browser are installed locally.
- The permanent keystore file remains outside the repository. Its path and alias are non-secret configuration; its password is a GNOME Keyring secret.
- Godot receives the keystore path, alias, and password only through `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` in the environment of the export subprocess.
- The package ID remains `org.danlil.animalheroes`.
- The release signer certificate is enrolled once and pinned thereafter. Changing it is a separate recovery project, not a normal dashboard action.

## System Overview

The system contains four independently testable units:

1. **Local dashboard and controller** — a Python standard-library service that exposes a localhost-only browser UI, owns release workflows, and serializes state-changing operations.
2. **Release pipeline and catalog** — isolated build, signing, validation, versioning, tagging, immutable artifact storage, and safe rollback logic.
3. **Device and deployment adapter** — Android Wireless ADB pairing, device identity resolution, coordinated two-tablet preflight/install/relaunch/verification, and recovery reporting.
4. **In-game update client** — Godot service discovery, one-time pairing, authenticated status/update requests, parent UI, and release/protocol compatibility checks.

The PC remains authoritative. A tablet may request an update, but it cannot choose an APK, change the active version, build, sign, promote, roll back, uninstall, or execute a command.

## PC Service Architecture

### Process model

One unprivileged Python process owns the dashboard, LAN API, UDP discovery responder, release catalog, audit log, and subprocess runner. It does not use `sudo` or install a system service. A repository launcher starts it, waits for readiness, and opens the browser. A generated desktop entry invokes that launcher.

Only one instance may run for a given catalog. An advisory lock prevents concurrent builds, releases, or deployments. Read-only dashboard and tablet-status requests remain available while a long operation is running.

### Interfaces

- **Dashboard:** HTTP on `127.0.0.1` only. Loopback scoping keeps it off the LAN; an unguessable per-process session token and CSRF protection defend its state-changing same-origin POST requests.
- **Tablet API:** HTTPS on one explicitly selected private-LAN address. It never binds to every interface by default. It exposes only discovery metadata, pairing, challenges, version status, and update requests.
- **UDP discovery:** a dedicated local-network port announces the tablet API address, protocol version, service instance ID, and certificate fingerprint. Discovery data is not trusted until pairing or pinned-certificate validation succeeds.

The dashboard and LAN API use separate route tables. There is no LAN route that reaches release, keystore, Git, artifact-selection, or arbitrary device controls.

### Dependencies

Runtime Python code uses the standard library. External commands are invoked through a narrow, allowlisted command adapter:

- `git`
- `godot`
- `adb`
- `aapt`
- `apksigner`
- `keytool` where certificate inspection requires it
- `openssl` for the local TLS identity
- `secret-tool` for GNOME Keyring access
- existing repository validation scripts

Executable resolution is explicit and validated at startup. No user-supplied string is evaluated by a shell.

## Local State and Data Model

State lives beneath the user's XDG directories, outside Git:

- Configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/animal-heroes-deploy/`
- Catalog, APKs, reports, and audit records: `${XDG_DATA_HOME:-$HOME/.local/share}/animal-heroes-deploy/`
- Runtime lock and port information: `${XDG_RUNTIME_DIR}/animal-heroes-deploy/`, or a mode-`0700` user-specific directory below `${TMPDIR:-/tmp}` when `XDG_RUNTIME_DIR` is unavailable

The implementation resolves and validates these paths once. Destructive operations may target only validated children of the catalog directory. Published artifacts are never removed automatically.

### Non-secret configuration

Configuration records:

- repository path;
- selected LAN address;
- keystore path and alias;
- expected package ID;
- pinned signer certificate SHA-256;
- host/client aliases and stable ADB hardware identities;
- dashboard and LAN ports;
- retention policy, fixed to retain all published releases in version one.

### Secrets

GNOME Keyring stores:

- release keystore password;
- the PC copy of each tablet HMAC token;
- the local TLS private-key passphrase if the generated key is encrypted.

Secrets are read only for the operation that needs them, supplied through subprocess standard input or a child-only environment, and discarded from application objects afterward. Logs replace secret-bearing fields with `[REDACTED]`.

The tablet stores its token and pinned PC certificate in Godot's Android app-private `user://` directory. This relies on the Android application sandbox; the design does not claim hardware-backed encryption from pure GDScript.

### Release catalog record

Each published release has an immutable metadata record containing:

- semantic `version_name`;
- monotonically increasing Android `version_code`;
- channel: `candidate` or `stable`;
- source Git commit and release commit;
- annotated Git tag;
- build timestamp and Godot/tool versions;
- package ID;
- APK size and SHA-256;
- signing-certificate SHA-256;
- exact permission set;
- application protocol version;
- save-schema version and compatible schema range;
- source release when the build is a safe rollback;
- automated gate results;
- human-gate evidence references;
- deployment results for both tablet identities.

The catalog is written atomically. APK paths are derived from catalog IDs rather than browser input.

## Pairing and Authentication

### Wireless ADB enrollment

The setup wizard accepts the pairing address and six-digit Android Wireless Debugging code shown by each tablet. It passes the code to `adb pair` over standard input, never through a command argument or log. It then connects, verifies that each device reports exactly `SM-T220`, reads a stable ADB hardware identity, assigns the host/client alias, and rejects duplicate devices.

Wireless ADB is the only mechanism allowed to install, stop, or relaunch the package. Revoking this PC under Android's Wireless Debugging settings disables deployment.

### Application pairing

The PC generates a persistent local TLS certificate. During application pairing, the dashboard displays a short-lived six-digit code derived from the current certificate fingerprint and a one-time pairing nonce. The parent opens the in-game admin panel and enters the code on the intended tablet.

The tablet uses the discovered HTTPS endpoint, checks that the displayed code matches the connected certificate and nonce, and exchanges a new random 256-bit per-tablet token. It pins the PC certificate and stores the token in app-private storage. The pairing code expires after five minutes and succeeds once.

Pairing is permitted only while the dashboard has an explicit pairing session open. The dashboard shows the requesting tablet role, LAN address, application-generated client ID, and matching ADB hardware identity before final acceptance. Pairing must be performed on the trusted private LAN.

### Authenticated requests

After pairing:

1. The tablet validates the pinned TLS certificate.
2. It obtains a single-use, short-lived server challenge.
3. It sends the client ID, action, challenge, and HMAC-SHA-256 signature created with its token.
4. The server verifies the certificate session, HMAC, client identity, challenge expiry, and unused status.
5. The server permanently consumes the challenge before starting an operation.

Replayed, expired, malformed, unknown-client, or wrong-HMAC requests return a generic rejection and create a redacted security audit event.

## Version and Compatibility Model

### Version source

A tracked release metadata file is the source of truth for:

- `version_name`;
- `version_code`;
- application protocol version;
- save-schema version;
- compatible save-schema range.

The build pipeline synchronizes Android export metadata and a generated in-game build-information resource from this file. Tests fail if the tracked metadata, exported APK metadata, and in-game metadata disagree.

### Ordering rules

- `version_code` is a positive integer and must be greater than every published catalog entry.
- `version_name` follows Semantic Versioning for display and tags.
- Candidate examples use `1.0.0-rc.1`; stable examples use `1.0.0`.
- Promoting a candidate to stable creates a new build with a new higher `version_code`; it does not relabel an existing APK.
- A rollback of older content is published as a new release version with a higher `version_code` and explicit `rollback_of` metadata.

### Game-session compatibility

The LAN handshake includes application protocol version, release version, and save-schema version. Peers with incompatible protocol versions cannot join. The UI presents a clear Hebrew message explaining which tablet needs an update. Release-name differences may join only when the declared protocol versions are compatible; the stable default is exact protocol compatibility.

## Release Lifecycle

### Candidate build

The dashboard collects the proposed candidate semantic version and release notes. Before changing state it requires:

- a clean tracked and untracked Git worktree, excluding documented ignored runtime artifacts;
- the expected branch and repository identity;
- no conflicting deployment/build lock;
- a readable external keystore;
- an unlocked keyring secret;
- a next version code greater than the catalog maximum.

The controller creates an isolated temporary Git worktree and a `codex/release-<version>` branch from the exact source commit. Inside that worktree it updates the tracked release metadata and changelog, then commits the release metadata. It runs the full test suite and release build there.

Signing uses Godot's supported release-keystore environment variables. The password is present only in the export subprocess environment and never printed. The output is staged outside the immutable catalog until all checks pass.

Required automated checks are:

1. full repository test suite;
2. successful Godot release export;
3. exact package-ID and version match;
4. exact four-permission allowlist;
5. `apksigner` cryptographic verification;
6. signing-certificate match against the pinned certificate;
7. APK SHA-256 generation and independent recheck;
8. build-information consistency;
9. catalog monotonicity and uniqueness.

Failure leaves the current branch, tags, active release, and immutable catalog unchanged. The failed staging directory is retained only when the operator explicitly asks to preserve diagnostic output.

After successful validation, the dashboard shows a final summary. On confirmation, it verifies that the original checkout has not changed, fast-forwards it to the isolated release commit, creates the annotated version tag, atomically publishes the APK and metadata, and optionally selects it as active. If a safe fast-forward is no longer possible, publication stops for manual reconciliation; the service never force-updates a branch.

### Stable promotion

Stable staging requires all candidate checks plus machine-readable evidence for:

- dual-SM-T220 functional, performance, thermal, and endurance validation;
- Hebrew language review;
- two supervised child-usability sessions;
- audio creator/source/license/distribution-rights provenance or approved replacement assets;
- release-keystore backup acknowledgement;
- successful install and smoke test of the exact candidate lineage.

Human checks must include an evidence path, date, and operator identity. The service validates completeness but does not pretend to automate human judgment. Promotion repeats the isolated-worktree, metadata, test, build, signing, and audit stages for a new stable APK with a higher version code from the approved source lineage. Unlike a candidate build, it does not fast-forward the current branch, create a tag, or publish the catalog record immediately. The exact staged stable APK must install on both tablets, relaunch successfully, report matching build information, and pass a recorded operator smoke check. Only then, and after confirming the original checkout is still unchanged, may the service fast-forward the release commit, create the stable tag, and atomically publish the stable artifact and record.

### Active release

Exactly one catalog release is active. It may be a candidate or stable release. The dashboard is the only interface allowed to change it. Tablet status responses and update requests always resolve the active catalog record at request time.

## Safe Rollback

Android normally blocks installing a lower release `version_code`. The system therefore never deploys an old APK as a downgrade.

To roll back:

1. The operator selects a prior catalog release produced by this managed metadata format.
2. The service checks that the target source can read the save-schema version currently deployed.
3. It creates a new semantic version and the next higher Android version code.
4. It rebuilds the prior source through the complete signed release pipeline.
5. The catalog records both the new release and its `rollback_of` source.
6. The operator activates and deploys the newly built rollback release.

If the selected release predates the managed metadata format or save compatibility is not declared, the service refuses the rollback. It never works around this by uninstalling the package or clearing data.

## Coordinated Two-tablet Deployment

### Preflight

Every deployment resolves both stored hardware identities to current ADB endpoints and verifies:

- two distinct authorized devices are online;
- both report exactly `SM-T220`;
- the APK is the active immutable catalog artifact;
- checksum, package, version, permissions, and signer still match the catalog;
- each tablet has sufficient storage;
- each tablet is charging or has at least 25% battery;
- no other deployment is active;
- first-install signature state is understood.

On clean tablets, first release enrollment installs normally. If an unexpected package with the same ID and a different signer exists, the service stops and requires an explicit local-dashboard confirmation before removal. Tablet requests can never authorize an uninstall.

### Update transaction

After both devices pass preflight:

1. Record before-state for both devices.
2. Notify the requesting game that the operation was accepted.
3. Stop Animal Heroes on both devices.
4. Install the active APK on the host and verify its installed package/version/signer.
5. Install it on the client and verify the same properties.
6. Retry a transient failed install once without uninstalling or clearing data.
7. Relaunch only successfully installed devices.
8. Poll both games for application-level readiness and matching build information.
9. Record checksums, versions, timing, command outcomes, and final state in the audit log and catalog deployment record.

An update cannot be perfectly atomic across two independent Android devices. If one device succeeds and the other fails, the dashboard marks the pair **version split**, highlights the failed recovery action, and retries only the failed device. The game-session compatibility gate prevents mismatched peers from starting a LAN session. The service never silently rolls the successful tablet backward.

### Tablet-triggered update

An authenticated tablet request always means **update both paired tablets to the PC-selected active release**. It cannot select a version or single device. If either tablet fails preflight, neither game is stopped and the requesting tablet receives a concise Hebrew explanation.

## User Interfaces

### Desktop setup wizard

The first-run wizard performs these steps:

1. Verify repository and required tools.
2. Select the private LAN interface.
3. Select the external keystore and enter its alias.
4. Store the password in GNOME Keyring and pin the signer certificate.
5. Pair and name the host tablet through Wireless ADB.
6. Pair and name the client tablet through Wireless ADB.
7. Open one application-pairing session per tablet.
8. Run a read-only connection and identity check.

The wizard never creates or deletes a keystore. It prominently requires an external backup before stable publication.

### Desktop dashboard

The overview shows, for both host and client:

- connection and authorization state;
- model and stable hardware identity suffix;
- battery and storage status;
- installed version name/code;
- compatibility and active-version status;
- last deployment result.

Release actions are:

- **Build candidate**
- **Promote to stable**
- **Set active**
- **Deploy both**
- **Relaunch both**
- **Safe rollback**
- **View validation report**
- **View redacted audit log**

Potentially destructive or source-changing actions show an explicit final summary. The UI never presents raw shell input.

### In-game parent panel

The existing Settings screen gains a parent section opened by a deliberate hold gesture. It uses Hebrew labels consistent with the game and shows:

- PC available/unavailable;
- paired/unpaired status;
- installed version;
- active version;
- up-to-date/update-available/incompatible state;
- one large **Update both tablets** button;
- pairing-code entry while a PC pairing session is open;
- progress or concise recovery guidance.

The button is disabled during active gameplay, while offline/unpaired, when both tablets are not ready, or while an update is already running. The game does not download or install APK bytes and does not request Android package-installer permissions.

## Error Handling and Recovery

- **PC offline or undiscovered:** show unavailable; make no state change.
- **TLS pin mismatch:** reject connection and require explicit re-pairing from the local dashboard.
- **Expired/replayed request:** reject generically and audit the event.
- **Keyring locked:** pause before build and ask the local desktop user to unlock it.
- **Wrong signer/package/permissions/checksum:** quarantine the staged APK; never publish or install it.
- **Dirty or changed Git checkout:** refuse release or final publication; never reset user changes.
- **Test/build failure:** leave Git refs, tags, catalog, and active release unchanged.
- **One tablet unavailable:** fail preflight before stopping either game.
- **Partial install:** mark version split, retry the failed device, prevent mismatched LAN play, and show the exact recovery step.
- **Low battery/storage:** refuse before stopping the game.
- **Save-schema incompatibility:** refuse rollback.
- **Audit/catalog write failure:** fail closed before changing the active release or beginning installation.

## Auditability

Every state-changing operation receives an operation ID and records:

- local timestamp;
- action and initiating interface;
- paired client ID or local dashboard session;
- source commit, version, APK checksum, and signer fingerprint;
- target hardware identities with only safe display suffixes;
- validation steps and exit status;
- deployment before/after versions;
- redacted error summaries.

Passwords, pairing codes, HMAC tokens, full private keys, and raw environment blocks are never logged. Audit records are append-only in normal operation and are not exposed over the LAN API.

## Testing Strategy

Implementation follows test-driven development.

### Python unit tests

- semantic version and monotonically increasing version-code validation;
- catalog atomicity and immutability;
- candidate/stable gate rules;
- safe rollback and save-schema compatibility;
- challenge expiry, single use, HMAC verification, and replay rejection;
- path containment and artifact-name validation;
- command allowlisting and secret redaction;
- deployment state-machine transitions and version-split recovery.

### Integration tests

- fake `git`, `godot`, Android SDK tools, `secret-tool`, and `adb` processes;
- credentials travel through standard input or child-only environment and do not enter logs/arguments;
- dirty-tree, changed-HEAD, failed-test, failed-signing, wrong-signer, wrong-permission, and checksum failures;
- two-device identity validation, duplicate/non-SM-T220 rejection, battery/storage preflight, install ordering, retry, relaunch, and post-install verification;
- local dashboard routes are unreachable through the LAN route table;
- TLS certificate enrollment, pinning, and re-pair behavior;
- published APKs and catalog entries remain unchanged after later operations.

### Godot headless tests

- update-client state transitions;
- discovery filtering and pinned service identity;
- pairing-code expiry and rejection states;
- challenge/HMAC request construction;
- parent-panel enable/disable logic and Hebrew messages;
- release/protocol compatibility handshake;
- version mismatch prevents a LAN session without transient acceptance.

### Repository and physical verification

- Run the existing complete test suite with the new tests included.
- Build a real signed candidate and independently audit its package metadata, permissions, signer, and checksum.
- Pair two physical `SM-T220` tablets over Wireless ADB.
- Pair both games with the PC service.
- Trigger an update from the dashboard and from one tablet.
- Verify both tablets relaunch on the same version and can complete LAN discovery/join.
- Exercise one controlled partial-failure recovery.
- Build and deploy one compatible safe rollback as a higher version code.
- Re-run the existing SM-T220 performance/endurance and usability gates on the exact signed candidate intended for stable promotion.

## Documentation and Operations

User documentation must cover:

- installing/removing the desktop shortcut;
- enabling and revoking Wireless Debugging;
- initial PC, keystore, and tablet setup;
- candidate and stable release creation;
- activating and deploying a version;
- tablet one-tap update;
- recovering an offline device or version split;
- safe rollback semantics;
- signer mismatch and clean-tablet enrollment;
- GNOME Keyring behavior;
- release-keystore backup and loss consequences;
- stopping the service and revoking application pairing.

The deployment service is manually started and does not run at login by default. Closing it removes the LAN update endpoint; the installed game continues to work normally.

## Acceptance Criteria

The feature is complete when:

1. The desktop shortcut starts the service and opens a localhost-only dashboard without installing Python packages.
2. Setup securely enrolls the external release keystore and exactly two distinct `SM-T220` tablets.
3. A candidate release can be created from a clean commit, fully tested, signed, verified, cataloged, tagged, and selected as active.
4. Stable publication refuses incomplete physical, language/usability, audio-rights, or signing-backup evidence.
5. The dashboard deploys the exact active APK to both tablets and verifies both installed versions.
6. A parent can request the same coordinated deployment with one in-game tap after opening the parent panel.
7. Neither the tablet API nor the game can select an arbitrary artifact, execute a command, expose a signing secret, uninstall an app, or clear data.
8. Replay, signer, package, permission, checksum, wrong-model, duplicate-device, low-battery/storage, dirty-tree, incompatible-save, and partial-install cases fail as specified.
9. Mismatched application protocols cannot start a LAN session.
10. A compatible prior source release can be rebuilt with a higher version code and deployed without clearing saves.
11. The complete automated suite passes and the two-tablet signed-release/update/rollback exercise is recorded.
