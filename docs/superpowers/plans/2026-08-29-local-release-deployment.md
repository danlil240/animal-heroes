# Animal Heroes Local Release Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a localhost release dashboard and parent-gated tablet client that safely version, sign, retain, and deploy Animal Heroes release APKs to two paired SM-T220 tablets over the private LAN.

**Architecture:** A Python-standard-library service owns immutable release state, signing, Git transactions, Wireless ADB, authentication, and the browser dashboard. Godot consumes generated release metadata, rejects incompatible LAN peers, and exposes a narrow paired update client plus Hebrew parent modal; tablets may request only the PC-selected active build for both devices.

**Tech Stack:** Python 3 standard library, vanilla HTML/CSS/JavaScript, Godot 4.7.2 typed GDScript, Bash, Git worktrees, GNOME Keyring (`secret-tool`), OpenSSL, Android SDK (`adb`, `aapt`, `apksigner`), OpenJDK 17

**Spec:** `docs/superpowers/specs/2026-08-29-local-release-deployment-design.md`

## Global Constraints

- Target only this Ubuntu/GNOME workstation, package `org.danlil.animalheroes`, and exactly two distinct devices reporting `SM-T220`.
- Use no third-party Python packages and add no Android permissions beyond `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, and `CHANGE_WIFI_MULTICAST_STATE`.
- Bind the dashboard to `127.0.0.1`; bind the tablet HTTPS API only to one explicitly selected private-LAN address.
- Keep the keystore outside Git and local deployment state. Keep its password and PC-side tablet tokens in GNOME Keyring.
- Never put passwords, pairing codes, tokens, or raw secret-bearing environments in argv, browser storage, persisted configuration, exceptions, or logs.
- Never use `shell=True`, `sudo`, `git reset --hard`, force-update a Git ref, deploy a browser-supplied APK path, or uninstall/clear app data from a tablet request.
- Published releases are immutable and retained indefinitely in version one.
- Android `version_code` is positive and monotonically increasing; tags are exactly `v{SemVer}`.
- Stable publication remains blocked by real physical, Hebrew/usability, audio-rights, and keystore-backup evidence. Tests must not manufacture those results.
- Rollback rebuilds managed prior source as a new higher-version release and refuses undeclared or incompatible save schemas.
- Follow TDD for every task and commit each independently reviewable deliverable.
- Run Python tests with `python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`.
- Run the repository gate with `bash scripts/test_all.sh`.

---

### Task 1: Establish Canonical Release Metadata and Generated Build Information

**Files:**
- Create: `release/metadata.json`
- Create: `release/gates.json`
- Create: `deploy/__init__.py`
- Create: `deploy/animal_heroes_deploy/__init__.py`
- Create: `deploy/animal_heroes_deploy/release_metadata.py`
- Create: `deploy/tests/__init__.py`
- Create: `deploy/tests/test_release_metadata.py`
- Create: `scripts/sync_release_metadata.py`
- Create: `game/core/build_info.gd`
- Modify: `game/core/game_config.gd:1-10`
- Modify: `game/autoload/save_store.gd:1-8`
- Modify: `game/export_presets.cfg:18-30`
- Modify: `game/tests/unit/test_project_smoke.gd:1-25`
- Modify: `scripts/test_all.sh:1-13`

**Interfaces:**
- Consumes: the existing Android export preset, save schema `1`, application protocol `1`, and full test runner.
- Produces: `ReleaseMetadata.load(path)`, `ReleaseMetadata.validate()`, `ReleaseMetadata.can_read_save_schema(schema)`, `sync_checkout(root, metadata)`, `check_checkout(root, metadata)`, `BuildInfo.current() -> Dictionary`, and a canonical tracked metadata source used by all later tasks.

- [ ] **Step 1: Write failing metadata validation and drift tests**

```python
class ReleaseMetadataTests(unittest.TestCase):
    def test_valid_metadata_and_schema_range(self):
        metadata = ReleaseMetadata.from_dict({
            "version_name": "1.0.0-dev.1",
            "version_code": 1,
            "application_protocol_version": 1,
            "save_schema_version": 1,
            "save_schema_compatible_min": 1,
            "save_schema_compatible_max": 1,
        })
        self.assertTrue(metadata.can_read_save_schema(1))
        self.assertFalse(metadata.can_read_save_schema(2))

    def test_rejects_unknown_keys_bad_semver_and_invalid_range(self):
        base = valid_metadata_dict()
        for patch in (
            {"extra": True},
            {"version_name": "release one"},
            {"version_code": 0},
            {"save_schema_compatible_min": 2},
        ):
            with self.subTest(patch=patch), self.assertRaises(MetadataError):
                ReleaseMetadata.from_dict(base | patch)

    def test_check_checkout_detects_generated_file_and_export_drift(self):
        root = make_checkout(self, version_name="wrong", version_code=99)
        with self.assertRaises(MetadataDriftError):
            check_checkout(root, ReleaseMetadata.load(root / "release/metadata.json"))
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run: `python3 -m unittest deploy.tests.test_release_metadata -v`  
Expected: FAIL because `deploy.animal_heroes_deploy.release_metadata` does not exist.

- [ ] **Step 3: Implement strict metadata parsing and atomic synchronization**

```python
@dataclass(frozen=True)
class ReleaseMetadata:
    version_name: str
    version_code: int
    application_protocol_version: int
    save_schema_version: int
    save_schema_compatible_min: int
    save_schema_compatible_max: int

    @classmethod
    def from_dict(cls, value: Mapping[str, object]) -> "ReleaseMetadata":
        if set(value) != REQUIRED_KEYS:
            raise MetadataError("release metadata keys are invalid")
        metadata = cls(**{key: value[key] for key in REQUIRED_KEYS})
        metadata.validate()
        return metadata

    def validate(self) -> None:
        if SEMVER.fullmatch(self.version_name) is None:
            raise MetadataError("version_name must be Semantic Versioning")
        integer_values = (
            self.version_code,
            self.application_protocol_version,
            self.save_schema_version,
            self.save_schema_compatible_min,
            self.save_schema_compatible_max,
        )
        if any(type(value) is not int or value <= 0 for value in integer_values):
            raise MetadataError("release numeric fields must be positive integers")
        if not self.save_schema_compatible_min <= self.save_schema_version <= self.save_schema_compatible_max:
            raise MetadataError("save schema compatibility range is invalid")
```

Create initial metadata with version `1.0.0-dev.1`, code `1`, protocol `1`, schema `1`, and compatible range `1..1`. Create `release/gates.json` with schema `1` and explicit `pending` entries for dual-SM-T220, Hebrew review, two child sessions, audio rights/replacement, and keystore backup. The sync function must atomically render all `BuildInfo` constants and only replace the two Android version lines in `export_presets.cfg`.

- [ ] **Step 4: Wire BuildInfo into GameConfig, SaveStore, and the smoke test**

```gdscript
class_name BuildInfo
extends RefCounted

const VERSION_NAME := "1.0.0-dev.1"
const VERSION_CODE := 1
const APPLICATION_PROTOCOL_VERSION := 1
const SAVE_SCHEMA_VERSION := 1
const SAVE_SCHEMA_COMPATIBLE_MIN := 1
const SAVE_SCHEMA_COMPATIBLE_MAX := 1

static func current() -> Dictionary:
	return {
		"version_name": VERSION_NAME,
		"version_code": VERSION_CODE,
		"application_protocol_version": APPLICATION_PROTOCOL_VERSION,
		"save_schema_version": SAVE_SCHEMA_VERSION,
	}
```

Set `GameConfig.PROTOCOL_VERSION = BuildInfo.APPLICATION_PROTOCOL_VERSION`, retain `CONTENT_VERSION = BuildInfo.VERSION_NAME` only as a display alias, set `GameConfig.UPDATE_DISCOVERY_PORT = 28742`, and set `SaveStore.CURRENT_VERSION = BuildInfo.SAVE_SCHEMA_VERSION`.

- [ ] **Step 5: Run focused and full tests**

Run: `python3 -m unittest deploy.tests.test_release_metadata -v && python3 scripts/sync_release_metadata.py --check && godot --headless --path game -s res://tests/unit/test_project_smoke.gd && bash scripts/test_all.sh`  
Expected: all commands exit `0`; the APK permission tests still require exactly the original four permissions.

- [ ] **Step 6: Commit**

```bash
git add release deploy scripts/sync_release_metadata.py scripts/test_all.sh game/core/build_info.gd game/core/game_config.gd game/autoload/save_store.gd game/export_presets.cfg game/tests/unit/test_project_smoke.gd
git commit -m "feat: establish managed release metadata"
```

### Task 2: Make LAN Compatibility Depend on Protocol, Not Release Name

**Files:**
- Modify: `game/network/protocol.gd:1-75`
- Modify: `game/network/discovery_service.gd:1-95`
- Modify: `game/autoload/session.gd:290-385`
- Modify: `game/ui/game_shell.gd`
- Modify: `game/ui/connection_overlay.gd`
- Modify: `game/tests/unit/test_protocol.gd`
- Modify: `game/tests/integration/test_discovery.gd`
- Modify: `game/tests/integration/test_connection_overlay.gd`
- Modify: `game/tests/integration/test_session_pair.gd`
- Modify: `scripts/run_lan_pair.sh`

**Interfaces:**
- Consumes: `BuildInfo.current()` and the existing ENet/UDP LAN flow.
- Produces: `Protocol.valid_build_descriptor(value)`, `Protocol.local_build_descriptor()`, `Protocol.compare_builds(local, remote)`, `DiscoveryService.incompatible_host_found(info)`, `Session._accept_lobby_character(peer_id, requested_character)`, and a pre-PLAYING handshake rejection using reason codes rather than remote text.

- [ ] **Step 1: Add failing compatibility and discovery tests**

```gdscript
func _test_build_compatibility(protocol) -> bool:
	var local := {"version_name": "1.0.0", "version_code": 10, "application_protocol_version": 2, "save_schema_version": 1}
	var newer_name := {"version_name": "1.1.0", "version_code": 11, "application_protocol_version": 2, "save_schema_version": 1}
	var incompatible := {"version_name": "2.0.0", "version_code": 12, "application_protocol_version": 3, "save_schema_version": 1}
	if not protocol.compare_builds(local, newer_name).get("compatible", false):
		return _fail("release-name differences with the same protocol must join")
	if protocol.compare_builds(local, incompatible).get("compatible", true):
		return _fail("application protocol mismatch must be rejected")
	return true
```

Extend the multi-process pair test with `--client-protocol=99` and assert the incompatible client never transiently reaches `PLAYING`. Add a regression asserting `GameShell._on_host_found()` uses `info["host"]`, not the nonexistent `address` key.

- [ ] **Step 2: Run RED tests**

Run: `godot --headless --path game -s res://tests/unit/test_protocol.gd && godot --headless --path game -s res://tests/integration/test_discovery.gd`  
Expected: FAIL because build descriptors and incompatible discovery signals do not exist.

- [ ] **Step 3: Implement strict descriptors and discovery routing**

```gdscript
static func compare_builds(local: Dictionary, remote: Dictionary) -> Dictionary:
	if not valid_build_descriptor(local) or not valid_build_descriptor(remote):
		return {"compatible": false, "reason": "unknown", "relation": "unknown"}
	var relation := "same"
	if int(local["version_code"]) < int(remote["version_code"]):
		relation = "local_older"
	elif int(local["version_code"]) > int(remote["version_code"]):
		relation = "remote_older"
	return {
		"compatible": int(local["application_protocol_version"]) == int(remote["application_protocol_version"]),
		"reason": "ok" if int(local["application_protocol_version"]) == int(remote["application_protocol_version"]) else "protocol_mismatch",
		"relation": relation,
	}
```

Discovery packets must contain `build`, validate its exact field types/ranges, and route incompatible valid advertisements to `incompatible_host_found` rather than silently treating them as joinable.

- [ ] **Step 4: Change the ENet lobby request before character insertion**

```gdscript
@rpc("any_peer", "reliable")
func request_lobby_entry(build: Dictionary, requested_character: String) -> void:
	if not _is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var comparison := Protocol.compare_builds(Protocol.local_build_descriptor(), build)
	if not bool(comparison.get("compatible", false)):
		reject_lobby_entry.rpc_id(peer_id, String(comparison.get("relation", "unknown")), Protocol.local_build_descriptor())
		_peer.disconnect_peer(peer_id)
		return
	_accept_lobby_character(peer_id, requested_character)
```

Map only local reason codes to the exact Hebrew messages in the design. Ensure the connection overlay remains visible after the session leaves. Preserve reconnect behavior and the two-player limit.

Extract the existing character validation, character assignment, `confirm_lobby_entry`, `peer_ready`, PLAYING transition, and traffic notification into `func _accept_lobby_character(peer_id: int, requested_character: String) -> void`; call it only after build compatibility succeeds.

- [ ] **Step 5: Run focused pair gates and full suite**

Run: `godot --headless --path game -s res://tests/unit/test_protocol.gd && godot --headless --path game -s res://tests/integration/test_discovery.gd && bash scripts/run_lan_pair.sh && bash scripts/run_reconnect_pair.sh && bash scripts/test_all.sh`  
Expected: compatible differing release names join, incompatible protocol never reaches `PLAYING`, third peer remains rejected, and all commands exit `0`.

- [ ] **Step 6: Commit**

```bash
git add game/network game/autoload/session.gd game/ui/game_shell.gd game/ui/connection_overlay.gd game/tests scripts/run_lan_pair.sh
git commit -m "feat: gate LAN sessions by managed protocol"
```

### Task 3: Add Safe Local Paths, Configuration, Domain Models, and Immutable Catalog

**Files:**
- Create: `deploy/animal_heroes_deploy/domain.py`
- Create: `deploy/animal_heroes_deploy/paths.py`
- Create: `deploy/animal_heroes_deploy/config.py`
- Create: `deploy/animal_heroes_deploy/catalog.py`
- Create: `deploy/tests/test_paths.py`
- Create: `deploy/tests/test_config.py`
- Create: `deploy/tests/test_catalog.py`

**Interfaces:**
- Consumes: `ReleaseMetadata` from Task 1.
- Produces: immutable `ReleaseRecord`, `DeviceIdentity`, `DeploymentRecord`, `StatePaths.resolve(env, uid)`, `require_child(base, candidate)`, `ConfigStore.load/save_atomic`, and `Catalog.list/get/publish/active/set_active/append_deployment`.

- [ ] **Step 1: Write failing XDG, containment, configuration, and catalog tests**

```python
class CatalogTests(unittest.TestCase):
    def test_publish_is_immutable_and_active_is_compare_and_swap(self):
        catalog = Catalog(StatePaths.for_test(self.temp_dir))
        release = release_record(version_name="1.0.0-rc.1", version_code=2)
        published = catalog.publish(self.apk, release)
        self.assertEqual(published.release_id, "0000000002-1.0.0-rc.1")
        self.assertEqual(catalog.active().release_id, published.release_id)
        with self.assertRaises(ReleaseExistsError):
            catalog.publish(self.apk, release)
        with self.assertRaises(StaleCatalogRevision):
            catalog.set_active(published.release_id, expected_revision=0)

    def test_require_child_rejects_parent_and_symlink_escape(self):
        outside = self.temp_dir.parent / "outside"
        outside.mkdir()
        (self.temp_dir / "link").symlink_to(outside, target_is_directory=True)
        for candidate in (self.temp_dir.parent, self.temp_dir / "link/file"):
            with self.subTest(candidate=candidate), self.assertRaises(PathBoundaryError):
                require_child(self.temp_dir, candidate)
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_paths deploy.tests.test_config deploy.tests.test_catalog -v`  
Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement focused immutable models and path boundaries**

```python
@dataclass(frozen=True)
class StatePaths:
    config: Path
    data: Path
    runtime: Path

    @classmethod
    def resolve(cls, env: Mapping[str, str], uid: int) -> "StatePaths":
        home = Path(env["HOME"]).resolve(strict=True)
        config = Path(env.get("XDG_CONFIG_HOME", home / ".config")) / APP_DIR
        data = Path(env.get("XDG_DATA_HOME", home / ".local/share")) / APP_DIR
        runtime_root = Path(env["XDG_RUNTIME_DIR"]) if env.get("XDG_RUNTIME_DIR") else Path(env.get("TMPDIR", "/tmp")) / f"animal-heroes-deploy-{uid}"
        return cls(config.resolve(strict=False), data.resolve(strict=False), (runtime_root / APP_DIR).resolve(strict=False))

def require_child(base: Path, candidate: Path) -> Path:
    resolved_base = base.resolve(strict=False)
    resolved_candidate = candidate.resolve(strict=False)
    if resolved_candidate == resolved_base or not resolved_candidate.is_relative_to(resolved_base):
        raise PathBoundaryError("path is outside the application state directory")
    return resolved_candidate
```

Use `os.open`/`os.replace`, `fsync`, mode `0700` directories, mode `0600` mutable JSON, and readonly published APK/metadata files. Catalog IDs are derived internally from validated version code/name. Store deployment records separately so release metadata remains immutable.

- [ ] **Step 4: Implement exact configuration invariants**

`DeployConfig.validate()` must require the fixed package ID, a selected private IPv4 address, a keystore path outside repository and state roots, exactly two distinct hardware identities with roles `host` and `client`, and no secret fields. Reject unknown JSON keys.

- [ ] **Step 5: Run focused tests and the Python suite**

Run: `python3 -m unittest deploy.tests.test_paths deploy.tests.test_config deploy.tests.test_catalog -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass; fault-injected atomic-write failures preserve the previous index and active pointer.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: add immutable local release catalog"
```

### Task 4: Enforce Process, Secret, and Redacted Audit Boundaries

**Files:**
- Create: `deploy/animal_heroes_deploy/commands.py`
- Create: `deploy/animal_heroes_deploy/toolchain.py`
- Create: `deploy/animal_heroes_deploy/secrets.py`
- Create: `deploy/animal_heroes_deploy/audit.py`
- Create: `deploy/tests/fake_tools.py`
- Create: `deploy/tests/test_commands.py`
- Create: `deploy/tests/test_secrets.py`
- Create: `deploy/tests/test_audit.py`
- Modify: `scripts/android_tools.sh:1-30`

**Interfaces:**
- Consumes: validated application paths and config from Task 3.
- Produces: `Tool`, `CommandRunner.run(tool, args, *, cwd=None, stdin=None, env_additions=None, secret_values=(), timeout_s=120.0) -> CommandResult`, `Toolchain.resolve_all()`, `GnomeKeyringSecretStore.store/lookup/clear`, `Redactor`, and append-only `AuditLog.append(event)`.

- [ ] **Step 1: Write failing allowlist and non-disclosure tests**

```python
class CommandBoundaryTests(unittest.TestCase):
    def test_secret_is_child_only_and_never_rendered(self):
        runner = fake_runner(self)
        result = runner.run(
            Tool.GODOT,
            ("--headless", "--version"),
            env_additions={"GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "super-secret"},
            secret_values=("super-secret",),
        )
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("super-secret", result.redacted_summary)
        self.assertNotIn("super-secret", " ".join(result.argv_display))

    def test_unknown_tool_and_arbitrary_bash_are_rejected(self):
        runner = fake_runner(self)
        with self.assertRaises(CommandPolicyError):
            runner.run_path(Path("/bin/sh"), ("-c", "id"))
        with self.assertRaises(CommandPolicyError):
            runner.run_repo_script(Path("outside.sh"))
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_commands deploy.tests.test_secrets deploy.tests.test_audit -v`  
Expected: FAIL because command, keyring, and audit modules do not exist.

- [ ] **Step 3: Implement an argv-only runner and tool resolver**

```python
class CommandRunner:
    def run(self, tool: Tool, args: Sequence[str], *, cwd: Path | None = None,
            stdin: bytes | None = None, env_additions: Mapping[str, str] | None = None,
            secret_values: Sequence[str] = (), timeout_s: float = 120.0) -> CommandResult:
        executable = self._resolved[tool]
        argv = (str(executable), *tuple(args))
        env = os.environ.copy()
        env.update(env_additions or {})
        completed = subprocess.run(argv, cwd=cwd, input=stdin, env=env, shell=False,
                                   capture_output=True, timeout=timeout_s, check=False)
        return CommandResult.from_completed(completed, self._redactor.with_values(secret_values))
```

Allow Bash only through `run_repo_script()` for canonical, explicitly registered repository scripts such as `scripts/test_all.sh` and `game/tests/device/apk_permissions.sh`. Extend Android tool resolution to include an executable `APKSIGNER_BIN`.

- [ ] **Step 4: Implement keyring and audit stores**

Use `secret-tool store` with the secret on stdin and `secret-tool lookup` output captured into a short-lived `bytearray`. Audit JSONL writes must be append-only, `fsync` each event, assign an operation UUID, structurally redact secret field names, and display only safe device-identity suffixes.

Enroll the release signer by invoking `keytool` with `-storepass:env AH_KEYSTORE_PASSWORD` in a child-only environment, normalize its SHA-256 certificate fingerprint, and pin it in non-secret configuration. Cross-check every APK against that fingerprint with `apksigner`; never pass a plaintext `-storepass` argument.

- [ ] **Step 5: Run security-focused and full Python tests**

Run: `python3 -m unittest deploy.tests.test_commands deploy.tests.test_secrets deploy.tests.test_audit -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass; fake tools prove passwords and pairing codes appear only in stdin or the child-only environment.

- [ ] **Step 6: Commit**

```bash
git add deploy scripts/android_tools.sh
git commit -m "feat: secure deployment process boundaries"
```

### Task 5: Implement TLS Identity, Pairing, Challenges, and LAN Discovery

**Files:**
- Create: `deploy/animal_heroes_deploy/auth.py`
- Create: `deploy/animal_heroes_deploy/tls_identity.py`
- Create: `deploy/animal_heroes_deploy/pairing.py`
- Create: `deploy/animal_heroes_deploy/discovery.py`
- Create: `deploy/tests/test_auth.py`
- Create: `deploy/tests/test_tls_identity.py`
- Create: `deploy/tests/test_pairing.py`
- Create: `deploy/tests/test_update_discovery.py`

**Interfaces:**
- Consumes: `CommandRunner`, `GnomeKeyringSecretStore`, `AuditLog`, and private LAN config.
- Produces: `canonical_auth_message`, `sign_message`, `ChallengeStore.issue/verify_and_consume`, `TlsIdentity.ensure`, `PairingManager.open/accept/revoke`, and `UpdateDiscoveryResponder.start/close`.

- [ ] **Step 1: Write failing fixed-vector, replay, pairing-expiry, and discovery tests**

```python
class AuthTests(unittest.TestCase):
    def test_fixed_vector_and_single_use(self):
        token = bytes.fromhex("00" * 32)
        message = canonical_auth_message("client_1", "update_both", "challenge_1")
        self.assertEqual(base64.b64encode(hmac.digest(token, message, "sha256")).decode(), sign_message(token, message))
        store = ChallengeStore(ttl=timedelta(seconds=30), random_bytes=lambda n: b"a" * n)
        challenge = store.issue("client_1", NOW)
        signature = sign_message(token, canonical_auth_message("client_1", "update_both", challenge.challenge_id))
        store.verify_and_consume("client_1", "update_both", challenge.challenge_id, signature, token, NOW)
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_1", "update_both", challenge.challenge_id, signature, token, NOW)
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_auth deploy.tests.test_tls_identity deploy.tests.test_pairing deploy.tests.test_update_discovery -v`  
Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement unambiguous authentication and one-use pairing**

```python
def canonical_auth_message(client_id: str, action: str, challenge: str) -> bytes:
    for value in (client_id, action, challenge):
        if SAFE_TOKEN.fullmatch(value) is None:
            raise AuthenticationError("invalid authentication field")
    return f"animal-heroes-update-v1\n{client_id}\n{action}\n{challenge}\n".encode("ascii")

def pairing_code(certificate_sha256: str, nonce: str) -> str:
    digest = hashlib.sha256(f"animal-heroes-pair-v1\n{certificate_sha256}\n{nonce}\n".encode("ascii")).digest()
    return f"{int.from_bytes(digest[:4], 'big') % 1_000_000:06d}"
```

Challenges expire after 30 seconds and are consumed under the mutation lock before an operation is queued. Pairing sessions expire after five minutes, work once, bind an intended role/device identity, and return a random 256-bit token only over the certificate-pinned pairing request.

- [ ] **Step 4: Generate TLS identity and strict UDP advertisements**

Generate the local certificate/key with allowlisted OpenSSL argv, owner-only permissions, and a stable SHA-256 fingerprint. Advertisements must remain below 1024 bytes and contain only protocol `1`, service instance ID, selected private IPv4, HTTPS port, pairing nonce when open, and 64-hex fingerprint.

- [ ] **Step 5: Run focused tests and Python suite**

Run: `python3 -m unittest deploy.tests.test_auth deploy.tests.test_tls_identity deploy.tests.test_pairing deploy.tests.test_update_discovery -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass, including wrong-HMAC, wrong-action, expired, replayed, oversized, and certificate-change cases.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: authenticate local tablet update requests"
```

### Task 6: Inspect APKs and Enroll/Probe Wireless ADB Devices

**Files:**
- Create: `deploy/animal_heroes_deploy/apk.py`
- Create: `deploy/animal_heroes_deploy/devices.py`
- Create: `deploy/tests/test_apk.py`
- Create: `deploy/tests/test_devices.py`

**Interfaces:**
- Consumes: toolchain, command runner, config, catalog paths, and pinned signer.
- Produces: `ApkInspector.inspect/verify`, `AdbAdapter.pair/connect/enroll/resolve/probe/inspect_installed/install/force_stop/launch`, immutable `ApkFacts`, `DeviceProbe`, and `InstalledPackage`.

- [ ] **Step 1: Write failing APK and device-boundary tests**

```python
class DeviceTests(unittest.TestCase):
    def test_enrollment_requires_two_distinct_exact_models(self):
        adb = fake_adb(models={"host": "SM-T220", "client": "SM-T220"}, serials={"host": "A", "client": "B"})
        self.assertNotEqual(adb.enroll("host", DeviceRole.HOST).hardware_id, adb.enroll("client", DeviceRole.CLIENT).hardware_id)
        with self.assertRaises(DeviceRejected):
            fake_adb(models={"phone": "Pixel 9"}).enroll("phone", DeviceRole.HOST)

    def test_preflight_battery_and_storage_boundaries(self):
        apk_size = 100 * 1024 * 1024
        self.assertFalse(device_probe(battery=24, charging=False, free=500 * 1024 * 1024).ready_for(apk_size))
        self.assertTrue(device_probe(battery=25, charging=False, free=500 * 1024 * 1024).ready_for(apk_size))
        self.assertTrue(device_probe(battery=5, charging=True, free=500 * 1024 * 1024).ready_for(apk_size))
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_apk deploy.tests.test_devices -v`  
Expected: FAIL because APK and ADB adapters do not exist.

- [ ] **Step 3: Implement exact APK verification**

Use `aapt dump badging`, `aapt dump permissions`, and `apksigner verify --verbose --print-certs`. Parse one package ID/name/code, a set of all declared permission forms, and exactly one signer. Independently compute and re-read SHA-256. Reject any difference from the fixed package, requested version, exact four permissions, pinned signer, or expected catalog checksum.

- [ ] **Step 4: Implement ADB identity and probe rules**

```python
class AdbAdapter:
    def pair(self, address: str, code: bytes) -> PairResult:
        return PairResult.parse(self.runner.run(Tool.ADB, ("pair", validate_endpoint(address)), stdin=code + b"\n", secret_values=(code.decode("ascii"),)))

    def enroll(self, endpoint: str, role: DeviceRole) -> DeviceIdentity:
        model = self.shell(endpoint, ("getprop", "ro.product.model")).strip()
        hardware_id = self.shell(endpoint, ("getprop", "ro.boot.serialno")).strip() or self.shell(endpoint, ("getprop", "ro.serialno")).strip()
        if model != "SM-T220" or not hardware_id:
            raise DeviceRejected("device must be an identifiable SM-T220")
        return DeviceIdentity(role=role, hardware_id=hardware_id, last_endpoint=endpoint)
```

Treat IP:port as a changing endpoint, never identity. Inspect an installed signer by resolving `pm path`, pulling `base.apk` into a validated runtime child, and using `apksigner`. Require battery `>=25%` or charging and free `/data` space of at least `max(2 * apk_size, 250 MiB)`.

Read `settings get secure android_id`, hash it with SHA-256, and expose only `DeviceProbe.device_binding_hash`. Pairing compares that hash to the tablet's SHA-256 of `OS.get_unique_id()`; raw Android IDs must not be persisted or logged. Keep the mapper injectable and mark the real SM-T220 equality check as a physical acceptance prerequisite.

- [ ] **Step 5: Run focused and full Python tests**

Run: `python3 -m unittest deploy.tests.test_apk deploy.tests.test_devices -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass, including unauthorized/offline, endpoint change, duplicate ID, wrong model, malformed output, absent package, signer conflict, and temp cleanup.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: verify releases and wireless tablets"
```

### Task 7: Stage and Publish Candidate Releases Transactionally

**Files:**
- Create: `deploy/animal_heroes_deploy/git_release.py`
- Create: `deploy/animal_heroes_deploy/release_pipeline.py`
- Create: `deploy/animal_heroes_deploy/operation_journal.py`
- Create: `deploy/tests/test_git_release.py`
- Create: `deploy/tests/test_release_pipeline.py`
- Create: `deploy/tests/test_operation_journal.py`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: metadata sync, catalog, secret store, command runner, APK inspector, and audit log.
- Produces: `ReleasePipeline.stage_candidate(request)`, `confirm_publish(operation_id)`, durable `StagedRelease`, `CheckoutSnapshot`, and recoverable publication journal states.

- [ ] **Step 1: Write failing stage/confirm transaction tests**

```python
class CandidatePipelineTests(unittest.TestCase):
    def test_stage_does_not_change_refs_catalog_or_active(self):
        harness = release_harness(self)
        before = harness.snapshot()
        staged = harness.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "First managed candidate", True))
        self.assertEqual(harness.snapshot(), before)
        self.assertEqual(staged.version_code, 2)

    def test_confirm_refuses_changed_checkout(self):
        harness = release_harness(self)
        staged = harness.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))
        harness.git.change_original_head()
        with self.assertRaises(CheckoutChanged):
            harness.pipeline.confirm_publish(staged.operation_id)
        self.assertEqual(harness.catalog.list_releases(), ())
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_git_release deploy.tests.test_release_pipeline deploy.tests.test_operation_journal -v`  
Expected: FAIL because release transactions do not exist.

- [ ] **Step 3: Implement isolated staging**

Define the request once and keep internal source/rollback selection unavailable to browser JSON:

```python
@dataclass(frozen=True)
class CandidateRequest:
    version_name: str
    release_notes: str
    activate: bool = False
    source_commit: str | None = None
    rollback_of: str | None = None
```

Dashboard parsing must construct only the first three fields. `RollbackPlanner` is the only caller permitted to populate `source_commit` and `rollback_of`.

Stage only from an exact configured repository/origin/branch with completely empty `git status --porcelain=v1 --untracked-files=all`. Compute code as `max(source_code, catalog_max)+1`; never accept a browser-supplied code/tag/path. Create a validated temporary worktree and strict `codex/release-<SemVer>` branch, update metadata/changelog, commit, run `scripts/test_all.sh`, and export into the operation staging directory:

```python
signing_env = {
    "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": str(config.keystore_path),
    "GODOT_ANDROID_KEYSTORE_RELEASE_USER": config.keystore_alias,
    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": password.decode("utf-8"),
}
runner.run(Tool.GODOT, ("--headless", "--path", str(worktree / "game"), "--export-release", "Android", str(staged_apk)),
           cwd=worktree, env_additions=signing_env, secret_values=(signing_env["GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"],), timeout_s=1800)
```

Validate tests, package, version, exact permissions, single pinned signer, checksum, metadata sync, catalog uniqueness, and monotonicity before returning a final summary.

- [ ] **Step 4: Implement journaled confirmation without force operations**

Preflight the catalog destination, recheck original HEAD/status, fast-forward only, create the annotated `v{SemVer}` tag, atomically publish, and then optionally activate. Journal states `STAGED`, `REFS_PREFLIGHTED`, `FAST_FORWARDED`, `TAGGED`, `CATALOG_PUBLISHED`, `ACTIVE_SET`, `COMPLETE`. On a crash, compare exact expected SHAs/paths and resume only provably idempotent work; otherwise report manual recovery. Never hard-reset or force-move a ref.

- [ ] **Step 5: Run fault-injection and full Python tests**

Run: `python3 -m unittest deploy.tests.test_git_release deploy.tests.test_release_pipeline deploy.tests.test_operation_journal -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass for dirty/untracked tree, wrong repo/branch, existing refs, failed suite/export/signing, changed HEAD, non-fast-forward, reused confirmation, and crashes after each journal state.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests CHANGELOG.md
git commit -m "feat: stage verified signed candidates"
```

### Task 8: Add Stable Evidence Gates and Safe Higher-version Rollback

**Files:**
- Create: `deploy/animal_heroes_deploy/evidence.py`
- Create: `deploy/animal_heroes_deploy/rollback.py`
- Create: `deploy/tests/test_evidence.py`
- Create: `deploy/tests/test_rollback.py`
- Modify: `deploy/animal_heroes_deploy/release_pipeline.py`
- Modify: `deploy/tests/test_release_pipeline.py`

**Interfaces:**
- Consumes: candidate pipeline, catalog, tracked gate file, and metadata compatibility ranges.
- Produces: `EvidenceEntry`, `EvidenceBundle`, `StableRequest`, `StagedSmokeEvidence`, `StagedStableCapability`, `PromotionGate.validate(bundle)`, `stage_stable(request)`, `publish_stable_after_smoke(staged_id, smoke_evidence)`, and `RollbackPlanner.prepare(source_release_id, new_version_name)`.

- [ ] **Step 1: Write failing evidence and rollback-direction tests**

```python
class RollbackTests(unittest.TestCase):
    def test_old_source_must_read_current_deployed_schema(self):
        source = release_record(save_min=1, save_max=1, source_commit="abc")
        current = release_record(save_schema=2, source_commit="def")
        with self.assertRaises(IncompatibleRollback):
            RollbackPlanner(catalog(source, current)).prepare(source.release_id, "1.1.1")

    def test_every_stable_gate_requires_evidence_path_date_and_operator(self):
        bundle = valid_evidence_bundle()
        for gate in REQUIRED_STABLE_GATES:
            invalid = replace_gate(bundle, gate, evidence_path="")
            with self.subTest(gate=gate), self.assertRaises(EvidenceRejected):
                PromotionGate().validate(invalid)
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_evidence deploy.tests.test_rollback -v`  
Expected: FAIL because stable gates and rollback planning do not exist.

- [ ] **Step 3: Implement stable staging and exact-artifact smoke gate**

```python
@dataclass(frozen=True)
class EvidenceEntry:
    evidence_path: str
    date: str
    operator: str

@dataclass(frozen=True)
class StableRequest:
    candidate_release_id: str
    version_name: str
    evidence: EvidenceBundle

@dataclass(frozen=True)
class StagedSmokeEvidence:
    staged_id: str
    apk_sha256: str
    host_hardware_id: str
    client_hardware_id: str
    host_version_code: int
    client_version_code: int
    operator: str
```

Require dual-SM-T220, Hebrew review, two child sessions, audio rights/replacement, keystore backup, and candidate-lineage install/smoke entries with nonempty evidence path, ISO date, and operator. Stable staging repeats the full build with a new SemVer/code from the approved source lineage but does not tag/publish. Accept stable publication only after both hardware identities report the exact staged APK version/signer and a local operator records smoke success.

- [ ] **Step 4: Implement rollback through the candidate pipeline**

```python
def prepare(self, source_release_id: str, new_version_name: str) -> CandidateRequest:
    source = self.catalog.get(source_release_id)
    current_schema = self.deployed_pair_schema()
    if not source.managed_metadata or not source.save_schema_min <= current_schema <= source.save_schema_max:
        raise IncompatibleRollback("selected source cannot read deployed saves")
    return CandidateRequest(version_name=new_version_name, release_notes=f"Safe rollback of {source.version_name}",
                            activate=False, source_commit=source.source_commit, rollback_of=source.release_id)
```

Refuse unmanaged source, missing commit, split/unknown deployed state, reused SemVer, or any request for a lower code, downgrade APK, uninstall, or automatic activation.

- [ ] **Step 5: Run focused and full Python tests**

Run: `python3 -m unittest deploy.tests.test_evidence deploy.tests.test_rollback deploy.tests.test_release_pipeline -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass; failed physical stable verification leaves no stable tag/catalog record.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: gate stable releases and safe rollback"
```

### Task 9: Coordinate Two-tablet Preflight, Installation, Recovery, and Readiness

**Files:**
- Create: `deploy/animal_heroes_deploy/deployment.py`
- Create: `deploy/tests/test_deployment.py`
- Modify: `deploy/animal_heroes_deploy/catalog.py`
- Modify: `deploy/animal_heroes_deploy/devices.py`

**Interfaces:**
- Consumes: active catalog record, APK/device inspection, audit, and two configured identities.
- Produces: `DeploymentCoordinator.preflight_active(initiator)`, `execute(plan)`, `validate_staged_stable(capability) -> StagedSmokeEvidence`, `retry_split_device(operation_id)`, `relaunch_both()`, and durable `DeploymentRecord` states including `COMPLETE`, `FAILED`, and `VERSION_SPLIT`.

- [ ] **Step 1: Write failing exact-order and partial-failure tests**

```python
class DeploymentTests(unittest.TestCase):
    def test_stops_nothing_when_any_preflight_fails(self):
        harness = deployment_harness(self, client_battery=24, client_charging=False)
        with self.assertRaises(PreflightRejected):
            harness.coordinator.preflight_active(Initiator.DASHBOARD)
        self.assertEqual(harness.adb.commands, [])

    def test_partial_client_failure_records_version_split(self):
        harness = deployment_harness(self, client_install_results=(TransportError(), TransportError()))
        result = harness.coordinator.execute(harness.coordinator.preflight_active(Initiator.TABLET))
        self.assertEqual(result.state, DeploymentState.VERSION_SPLIT)
        self.assertEqual(harness.adb.install_roles, [DeviceRole.HOST, DeviceRole.CLIENT, DeviceRole.CLIENT])
        self.assertNotIn("uninstall", harness.adb.command_names)
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_deployment -v`  
Expected: FAIL because the coordinator does not exist.

- [ ] **Step 3: Implement fail-closed preflight and TOCTOU recheck**

Pin active release ID/hash and fresh probes for both identities. Verify exact active artifact, authorization, distinct SM-T220 models/IDs, battery/storage, installed signer state, audit/catalog writability, and no mutation lock. Immediately before force-stop, re-read active revision/hash and hardware identities; reject any change.

- [ ] **Step 4: Implement deterministic install and recovery state machine**

Stop both only after full preflight. Install/verify host, then client. Retry exactly once only for classified transient ADB transport failure. If host permanently fails, leave client untouched and relaunch the old pair. If host succeeds and client fails, record `VERSION_SPLIT`, relaunch verified devices only, and expose retry for the failed device. Poll application readiness/build info before `COMPLETE`.

Signature-mismatch clean enrollment is a separate local-dashboard confirmation bound to exact device identity, observed signer, and expiry. Tablet initiators can never authorize it.

`validate_staged_stable()` accepts only the unforgeable internal capability created by `stage_stable`, pins its staged path/hash/version, deploys that exact artifact to both devices, and returns smoke evidence only after both report readiness. It does not expose a generic non-active APK deployment path to dashboard or LAN request parsing.

- [ ] **Step 5: Run state-machine and full tests**

Run: `python3 -m unittest deploy.tests.test_deployment -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all ordering, transient/permanent failure, active-change, post-install mismatch, readiness-timeout, audit failure, and split-recovery cases pass.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: coordinate dual-tablet deployment"
```

### Task 10: Expose Split Local/LAN APIs and a Local Browser Dashboard

**Files:**
- Create: `deploy/animal_heroes_deploy/http_api.py`
- Create: `deploy/animal_heroes_deploy/controller.py`
- Create: `deploy/animal_heroes_deploy/service.py`
- Create: `deploy/animal_heroes_deploy/templates/dashboard.html`
- Create: `deploy/animal_heroes_deploy/static/dashboard.css`
- Create: `deploy/animal_heroes_deploy/static/dashboard.js`
- Create: `deploy/tests/test_http_api.py`
- Create: `deploy/tests/test_controller.py`
- Create: `deploy/tests/test_service.py`

**Interfaces:**
- Consumes: release pipeline, catalog, pairing/auth, discovery, device/deployment coordinator.
- Produces: `dashboard_routes(controller)`, `tablet_routes(controller)`, `Controller.status/start_operation/operation_status`, `TabletController.status/request_update`, and `DeployService.start/close`.

- [ ] **Step 1: Write failing route-isolation, CSRF, body-limit, and tablet-capability tests**

```python
class HttpApiTests(unittest.TestCase):
    def test_lan_routes_cannot_build_activate_rollback_or_uninstall(self):
        lan = tablet_routes(fake_tablet_controller())
        for path in ("/v1/build", "/v1/active", "/v1/rollback", "/v1/uninstall", "/api/releases"):
            self.assertIsNone(lan.match("POST", path))

    def test_tablet_update_has_no_artifact_or_device_parameters(self):
        response = self.lan.post_authenticated("/v1/update", {"release_id": "evil", "device": "host"})
        self.assertEqual(response.status, 400)
        self.assertEqual(self.controller.update_calls, [])
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_http_api deploy.tests.test_controller deploy.tests.test_service -v`  
Expected: FAIL because servers, controllers, and routes do not exist.

- [ ] **Step 3: Implement hardened fixed route tables**

Use `ThreadingHTTPServer` with no directory serving, fixed JSON/body limits, timeouts, explicit content types, redacted access logs, and exact method/path matching. Wrap only the LAN server socket in the pinned TLS context. Dashboard routes require the one-use bootstrap session plus same-origin CSRF. LAN routes are limited to:

```text
GET  /v1/pairing-certificate
POST /v1/pair
POST /v1/challenge
POST /v1/status
POST /v1/update
POST /v1/readiness
```

Dashboard routes cover setup, status, releases, stage/confirm candidate, stable stage/confirm, activate, deploy, relaunch, rollback, pairing sessions, operation status, and redacted audit reads.

- [ ] **Step 4: Implement the dashboard without framework dependencies**

Render two device cards, release table, active version, operation log, setup wizard, and buttons defined in the spec. JavaScript sends only JSON to same-origin endpoints with the CSRF header and polls operation status. It never stores keystore password, pairing code, token, APK path, or raw shell input.

- [ ] **Step 5: Run HTTP/controller tests and Python suite**

Run: `python3 -m unittest deploy.tests.test_http_api deploy.tests.test_controller deploy.tests.test_service -v && python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`  
Expected: all tests pass, dashboard is unreachable via the LAN listener, and mutation operations serialize while status remains readable.

- [ ] **Step 6: Commit**

```bash
git add deploy/animal_heroes_deploy deploy/tests
git commit -m "feat: add local release dashboard"
```

### Task 11: Add App-private Pairing, Updater Protocol, and Pinned Tablet API Client

**Files:**
- Create: `game/update/update_pairing_store.gd`
- Create: `game/update/update_protocol.gd`
- Create: `game/update/update_discovery.gd`
- Create: `game/update/tablet_api_client.gd`
- Create: `game/tests/unit/test_update_pairing_store.gd`
- Create: `game/tests/unit/test_update_protocol.gd`
- Create: `game/tests/integration/test_tablet_api_client.gd`

**Interfaces:**
- Consumes: Task 5 protocol vectors, Task 10 LAN routes, BuildInfo, and `GameConfig.UPDATE_DISCOVERY_PORT`.
- Produces: atomic `UpdatePairingStore`, `UpdateProtocol.decode_service_discovery`, `certificate_sha256_from_pem`, `pairing_code`, `canonical_auth_message`, `hmac_sha256_base64`, expiring `UpdateDiscovery`, and `TabletApiClient.request_pairing/request_status/request_update/report_readiness/cancel`.

- [ ] **Step 1: Write failing GDScript store and protocol-vector tests**

```gdscript
func _test_auth_vector(protocol) -> bool:
	var token := PackedByteArray()
	token.resize(32)
	var message := protocol.canonical_auth_message("client_1", "update_both", "challenge_1")
	var expected := "g4gVSxZfYbsORsqEmd+1dBfjFqfpdQxMWVGhcHEAEcQ="
	var actual := protocol.hmac_sha256_base64(token, message)
	if actual != expected:
		return _fail("HMAC must match the Python fixed vector")
	return true
```

Use the exact expected Base64 string generated by the Python Task 5 fixed-vector test, not a self-derived expectation. Store tests cover valid atomic round trip, malformed/partial rejection, failed promotion preserving the old record, clear removing temp/backup, and proof that the token never enters `SaveStore`.

- [ ] **Step 2: Run RED tests**

Run: `godot --headless --path game -s res://tests/unit/test_update_pairing_store.gd && godot --headless --path game -s res://tests/unit/test_update_protocol.gd`  
Expected: FAIL because update modules do not exist.

- [ ] **Step 3: Implement strict updater protocol and app-private store**

```gdscript
static func canonical_auth_message(client_id: String, action: String, challenge: String) -> PackedByteArray:
	if not _safe_token(client_id) or not _safe_token(action) or not _safe_token(challenge):
		return PackedByteArray()
	return ("animal-heroes-update-v1\n%s\n%s\n%s\n" % [client_id, action, challenge]).to_utf8_buffer()

static func hmac_sha256_base64(token: PackedByteArray, message: PackedByteArray) -> String:
	var context := HMACContext.new()
	if context.start(HashingContext.HASH_SHA256, token) != OK:
		return ""
	context.update(message)
	return Marshalls.raw_to_base64(context.finish())
```

Pairing storage schema contains only schema `1`, client ID, hashed device binding, service ID, pinned certificate PEM/fingerprint, and Base64 token in `user://animal-heroes-update-pairing.json` using temp/backup promotion.

- [ ] **Step 4: Implement safe certificate bootstrap and pinned requests**

During an explicitly open pairing session, retrieve only PEM/nonce using unsafe TLS, hash the PEM, verify the UDP fingerprint and entered six-digit code, then create `TLSOptions.client()` from that exact PEM and repeat the token exchange over the pinned connection. Never send code/token or accept pairing on the unsafe request. All later status/update/readiness calls use pinned TLS, a fresh challenge, and HMAC.

Use SHA-256 of `OS.get_unique_id()` as the initial device-binding hash and make the ID provider injectable for tests. Record physical validation as pending until both SM-T220s confirm it matches hashed Android ID from ADB.

- [ ] **Step 5: Run focused and full Godot tests**

Run: `godot --headless --path game -s res://tests/unit/test_update_pairing_store.gd && godot --headless --path game -s res://tests/unit/test_update_protocol.gd && godot --headless --path game -s res://tests/integration/test_tablet_api_client.gd && bash scripts/test_all.sh`  
Expected: all tests pass; no new Android permission is introduced.

- [ ] **Step 6: Commit**

```bash
git add game/update game/tests
git commit -m "feat: add authenticated tablet update client"
```

### Task 12: Orchestrate Update State and Add the Hebrew Parent Modal

**Files:**
- Create: `game/autoload/update_client.gd`
- Create: `game/ui/parent_update_panel.gd`
- Create: `game/ui/parent_update_panel.tscn`
- Create: `game/tests/integration/test_update_client.gd`
- Create: `game/tests/integration/test_parent_update_panel.gd`
- Modify: `game/project.godot:10-20`
- Modify: `game/ui/settings_screen.gd`
- Modify: `game/ui/settings_screen.tscn`
- Modify: `game/ui/game_shell.gd`
- Modify: `game/tests/integration/test_hebrew_ui.gd`

**Interfaces:**
- Consumes: tablet API client/store, BuildInfo, Session state, existing Settings screen.
- Produces: `UpdateClient.start/stop/submit_pairing_code/refresh_status/request_update_both/status_snapshot/paired`, signals `state_changed/status_changed/pairing_succeeded/update_accepted/update_failed`, and `ParentUpdatePanel.render(snapshot, session_state)` with `pairing_requested/update_requested/close_requested` signals.

- [ ] **Step 1: Write failing state-machine, hold, layout, and Hebrew-copy tests**

```gdscript
func _test_update_refusal(client) -> bool:
	client.set_dependencies_for_test(fake_discovery, fake_api, fake_store, fake_session)
	fake_session.state = "playing"
	client.request_update_both()
	if fake_api.update_requests != 0:
		return _fail("updates must be refused outside IDLE")
	fake_session.state = "idle"
	fake_api.snapshot = {"pc_available": true, "paired": true, "both_ready": true, "compatible": true}
	client.request_update_both()
	if fake_api.update_requests != 1:
		return _fail("one safe request must update both tablets")
	return true
```

Panel tests assert RTL, no clipping at `1340x800` and `1024x600`, every target at least `96x96`, short hold does nothing, `1.5` seconds opens, exactly six ASCII digits are accepted, exact Hebrew states render, and update is disabled for offline/unpaired/not-both-ready/incompatible/updating/non-IDLE.

- [ ] **Step 2: Run RED tests**

Run: `godot --headless --path game -s res://tests/integration/test_update_client.gd && godot --headless --path game -s res://tests/integration/test_parent_update_panel.gd`  
Expected: FAIL because update orchestration and parent UI do not exist.

- [ ] **Step 3: Implement UpdateClient state and safe request guard**

```gdscript
func request_update_both() -> void:
	if Session.state != Session.IDLE or not paired() or not bool(_snapshot.get("pc_available", false)) or not bool(_snapshot.get("both_ready", false)) or not bool(_snapshot.get("compatible", false)) or _request_in_flight:
		update_failed.emit("not_ready")
		return
	_request_in_flight = true
	_set_state("updating")
	_api.request_update(_store.load_pairing())
```

Register `UpdateClient` as an autoload. Start discovery/readiness from `GameShell` startup so a relaunched app can report its exact BuildInfo. Durable progress remains on the PC because ADB may stop the requester immediately after HTTP `202`.

- [ ] **Step 4: Implement the modal rather than growing Settings vertically**

Move the Settings title into an HBox with a `96x96` `לחיצה ארוכה להורים` target. Use deterministic `advance_parent_hold(delta)` with threshold `1.5`, cancel on release/exit, and open a separate full-screen RTL modal. Wire pairing/update/close signals to UpdateClient and render the exact Hebrew copy from the spec.

- [ ] **Step 5: Run UI, LAN, and full repository gates**

Run: `godot --headless --path game -s res://tests/integration/test_update_client.gd && godot --headless --path game -s res://tests/integration/test_parent_update_panel.gd && godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd && bash scripts/run_lan_pair.sh && bash scripts/test_all.sh`  
Expected: all tests pass at both resolutions and existing audio/settings behavior remains intact.

- [ ] **Step 6: Commit**

```bash
git add game/autoload/update_client.gd game/project.godot game/ui game/tests/integration
git commit -m "feat: add parent-gated tablet updates"
```

### Task 13: Add Launcher, Setup Documentation, End-to-end Harness, and Final Verification

**Files:**
- Create: `deploy/animal_heroes_deploy/__main__.py`
- Create: `deploy/run.py`
- Create: `scripts/animal_heroes_deploy.sh`
- Create: `scripts/install_animal_heroes_deploy_shortcut.sh`
- Create: `deploy/tests/test_end_to_end.py`
- Create: `deploy/tests/test_launcher.py`
- Create: `docs/local-release-deployment.md`
- Modify: `docs/android-build.md`
- Modify: `docs/release-checklist.md`
- Modify: `.gitignore`
- Modify: `scripts/test_all.sh`

**Interfaces:**
- Consumes: all prior PC and Godot components.
- Produces: `python3 -m deploy.animal_heroes_deploy`, `render_desktop_entry(repo_root) -> str`, manual desktop launcher, fake-tool end-to-end release/deployment coverage, and operator documentation.

- [ ] **Step 1: Write failing end-to-end and launcher tests**

```python
class EndToEndTests(unittest.TestCase):
    def test_candidate_pair_activate_deploy_update_and_rollback(self):
        app = fake_application(self, two_sm_t220=True)
        candidate = app.build_and_publish_candidate("1.0.0-rc.1")
        app.set_active(candidate.release_id)
        app.deploy_both()
        self.assertEqual(app.installed_codes(), (candidate.version_code, candidate.version_code))
        operation = app.tablet_request_update("host-client-id")
        self.assertEqual(operation.state, "complete")
        rollback = app.stage_compatible_rollback(candidate.release_id, "1.0.0-rc.2")
        self.assertGreater(rollback.version_code, candidate.version_code)

class LauncherTests(unittest.TestCase):
    def test_launcher_binds_dashboard_to_loopback_and_has_no_autostart(self):
        desktop = render_desktop_entry(Path("/repo"))
        self.assertIn("Animal Heroes Deploy", desktop)
        self.assertNotIn("autostart", desktop.lower())
```

- [ ] **Step 2: Run RED tests**

Run: `python3 -m unittest deploy.tests.test_end_to_end deploy.tests.test_launcher -v`  
Expected: FAIL because the entry point, launcher, and integrated harness do not exist.

- [ ] **Step 3: Implement entry point and recoverable launcher**

`deploy/run.py` and `python3 -m deploy.animal_heroes_deploy` must resolve configuration, acquire the runtime lock, start loopback/LAN/discovery listeners, print only redacted readiness, and close cleanly on SIGINT/SIGTERM. The shell launcher waits for the loopback health endpoint before using `xdg-open` with a one-use bootstrap URL. The shortcut installer writes only the explicit user application entry and never installs autostart state.

- [ ] **Step 4: Document exact setup and recovery operations**

Document enabling/revoking Wireless Debugging, separate pair/connect ports, keystore selection/backup, keyring unlock, desktop shortcut install/removal, candidate/stable/active flows, in-game pairing, one-tap update, version split, signer conflict on clean enrollment, safe rollback, service stop/revocation, and the limitation that real stable gates remain pending until recorded on physical tablets.

- [ ] **Step 5: Run all automated verification from a clean worktree**

Run:

```bash
python3 scripts/sync_release_metadata.py --check
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v
bash scripts/test_all.sh
git diff --check
git status --short
```

Expected: metadata check, Python suite, and full Godot/shell suite exit `0`; `git diff --check` is clean; status contains only intentional Task 13 changes before commit.

- [ ] **Step 6: Run non-destructive real local checks**

Run: `python3 -m deploy.animal_heroes_deploy --check`  
Expected: toolchain and loopback configuration pass; missing keystore, keyring enrollment, or physical tablets are reported as external setup prerequisites rather than fabricated success.

- [ ] **Step 7: Commit**

```bash
git add deploy scripts docs .gitignore
git commit -m "feat: complete local tablet release deployment"
```

- [ ] **Step 8: Execute physical acceptance when prerequisites are available**

Run the real signed candidate pipeline, independently inspect it with `aapt` and `apksigner`, pair two Wireless ADB SM-T220s, pair both in-game clients, deploy from dashboard, deploy from tablet, exercise a controlled client failure/retry, verify LAN join, and rebuild/deploy one compatible rollback with a higher code. Then repeat the existing performance/endurance, Hebrew, child-usability, audio-rights, and stable-release gates on the exact approved lineage.

Expected: physical results are recorded only from real hardware and human sessions. Until the keystore, two tablets, audio provenance/replacements, native Hebrew reviewer, and child sessions exist, candidate tooling may be complete but stable publication remains blocked.
