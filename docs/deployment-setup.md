# Animal Heroes Local Release and Deployment Setup

This guide covers the one-time setup for the household deployment system
that builds, signs, verifies, and deploys Animal Heroes release APKs to
two paired Samsung Galaxy Tab A7 Lite (SM-T220) tablets over the private LAN.

## Prerequisites

### Workstation (Ubuntu/GNOME)

- Python 3.12+ (standard library only, no pip packages)
- Git
- OpenSSL
- GNOME Keyring (`secret-tool` from `libsecret-tools`)
- OpenJDK 17
- Android SDK with:
  - `platform-tools/adb`
  - `build-tools/<version>/aapt`
  - `build-tools/<version>/apksigner`
- Godot 4.7.2

### Tablets

- Exactly two Samsung Galaxy Tab A7 Lite Wi-Fi (SM-T220)
- Wireless ADB enabled (Developer Options > Wireless Debugging)
- Both tablets on the same private LAN as the workstation

## One-time Setup

### 1. Android SDK

```bash
# Verify tools are resolvable
source scripts/android_tools.sh
resolve_android_tools
echo "$ADB_BIN $AAPT_BIN $APKSIGNER_BIN"
```

### 2. Release Keystore

Create a release keystore outside the repository and state directories:

```bash
keytool -genkey -v -keystore ~/keystores/animal-heroes-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias animalheroes
```

Store the keystore password in GNOME Keyring:

```bash
secret-tool store application animal-heroes-deploy key release-keystore-password
```

### 3. Deployment Configuration

Create `release/deploy_config.json`:

```json
{
  "package_id": "org.danlil.animalheroes",
  "lan_address": "192.168.1.100",
  "lan_port": 8443,
  "dashboard_port": 8442,
  "discovery_port": 28742,
  "keystore_path": "/home/<user>/keystores/animal-heroes-release.jks",
  "keystore_alias": "animalheroes",
  "pinned_signer_sha256": "<64 hex chars from apksigner --print-certs>",
  "devices": [
    {"role": "host", "hardware_id": "R28M30XXXXXX"},
    {"role": "client", "hardware_id": "R28M30YYYYYY"}
  ],
  "retention": "retain_all"
}
```

### 4. Pair Tablets

1. On each tablet: Developer Options > Wireless Debugging > Pair device with code
2. On the workstation:

```bash
adb pair <tablet-ip>:<pairing-port>
# Enter the pairing code shown on the tablet
```

3. Enroll each tablet:

```bash
# The deployment service enrolls devices on first connection
# and verifies model SM-T220 and hardware serial
```

### 5. Verify Setup

```bash
# Non-destructive check
python3 -m deploy.animal_heroes_deploy --check

# Full test suite
python3 scripts/sync_release_metadata.py --check
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v
bash scripts/test_all.sh
```

## Running the Dashboard

```bash
python3 -m deploy.animal_heroes_deploy
```

The dashboard is available only at `http://127.0.0.1:<dashboard_port>`.

## Recovery

If the deployment service crashes during publication:

1. Check the operation journal in `$XDG_RUNTIME_DIR/animal-heroes-deploy/journal/`
2. The catalog and Git refs are never modified until all preflight checks pass
3. Staged worktrees are cleaned up on failure or can be removed with `git worktree prune`

If a deployment leaves the tablets in a version split:

1. The dashboard shows `VERSION_SPLIT` state
2. Use "Retry failed device" to install only the failed tablet
3. Never uninstall or clear app data as a recovery method

## Stable Promotion

Stable promotion requires real evidence for all gates:

- `dual_sm_t220`: Two physical SM-T220 tablets verified
- `hebrew_review`: Hebrew text reviewed by a Hebrew reader
- `two_child_sessions`: Two child usability sessions completed
- `audio_rights_or_replacement`: Audio rights documented or replacements verified
- `keystore_backup`: Keystore backed up to a secure location
- `candidate_lineage_install_smoke`: Candidate install smoke test passed

No stable release should be claimed until all gates have real evidence.
