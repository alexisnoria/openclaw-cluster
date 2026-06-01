#!/usr/bin/env bats
# tests/bats/backup.bats — pure-FS tests for cluster_backup + cluster_restore.
# No docker needed.

setup() {
  load helpers/load
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/lib/backup.sh"

  TEST_TMPDIR="$(mktemp -d -t oc-backup-XXXXXX)"
  export INSTANCES_DIR="${TEST_TMPDIR}/instances"
  export CLUSTER_DIR="${TEST_TMPDIR}"
  export TEMPLATE_FILE="${ROOT_DIR}/docker-compose.template.yml"
  mkdir -p "${INSTANCES_DIR}"

  # Create a fake instance-1 to back up
  mkdir -p "${INSTANCES_DIR}/instance-1/config"
  printf '{"hello":"world"}' > "${INSTANCES_DIR}/instance-1/config/openclaw.json"
  printf 'a%.0s' {1..64} > "${INSTANCES_DIR}/instance-1/.token"
  # Cluster .env for restore to find TZ/HEADLESS
  printf 'TZ=UTC\nHEADLESS=yes\n' > "${TEST_TMPDIR}/.env"
  cd "${TEST_TMPDIR}"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# ----------------------------------------------------------------------------
# cluster_backup
# ----------------------------------------------------------------------------

@test "cluster_backup creates a tar.gz in backups/" {
  run cluster_backup 1
  [ "$status" -eq 0 ]
  [ -d "${TEST_TMPDIR}/backups" ]
  # Exactly one backup file
  count=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "cluster_backup returns the backup file path" {
  run cluster_backup 1
  [ "$status" -eq 0 ]
  # Last line of stdout is the file path
  path=$(echo "$output" | tail -n1)
  [[ "$path" == *"backups/instance-1_"* ]]
  [[ "$path" == *".tar.gz" ]]
  [ -f "$path" ]
}

@test "cluster_backup tarball contains instance-1/" {
  cluster_backup 1 >/dev/null
  tarball=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1)
  tar -tzf "$tarball" | grep -q 'instance-1/'
  tar -tzf "$tarball" | grep -q 'instance-1/config/openclaw.json'
}

@test "cluster_backup timestamp is in YYYYMMDD_HHMMSS format" {
  cluster_backup 1 >/dev/null
  fname=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1 | xargs basename)
  [[ "$fname" =~ ^instance-1_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]]
}

@test "cluster_backup fails for non-existent instance" {
  run cluster_backup 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "cluster_backup creates backups/ if missing" {
  [ ! -d "${TEST_TMPDIR}/backups" ]
  cluster_backup 1 >/dev/null
  [ -d "${TEST_TMPDIR}/backups" ]
}

# ----------------------------------------------------------------------------
# cluster_restore
# ----------------------------------------------------------------------------

@test "cluster_restore extracts files to the target instance" {
  cluster_backup 1 >/dev/null
  tarball=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1)
  # Wipe instance-1, then restore
  rm -rf "${INSTANCES_DIR}/instance-1"
  mkdir -p "${INSTANCES_DIR}"

  cluster_restore "$tarball" 1 >/dev/null
  [ -d "${INSTANCES_DIR}/instance-1/config" ]
  [ -f "${INSTANCES_DIR}/instance-1/config/openclaw.json" ]
  [ -f "${INSTANCES_DIR}/instance-1/docker-compose.yml" ]
  [ -f "${INSTANCES_DIR}/instance-1/.env" ]
}

@test "cluster_restore rewrites the .env with a fresh token" {
  cluster_backup 1 >/dev/null
  tarball=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1)
  rm -rf "${INSTANCES_DIR}/instance-1"
  mkdir -p "${INSTANCES_DIR}"

  cluster_restore "$tarball" 1 >/dev/null
  token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "${INSTANCES_DIR}/instance-1/.env" | cut -d= -f2)
  [[ "$token" =~ ^[0-9a-f]{64}$ ]]
}

@test "cluster_restore rewrites the token in openclaw.json" {
  cluster_backup 1 >/dev/null
  tarball=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1)
  rm -rf "${INSTANCES_DIR}/instance-1"
  mkdir -p "${INSTANCES_DIR}"

  cluster_restore "$tarball" 1 >/dev/null
  json_token=$(jq -r '.gateway.auth.token // .token' "${INSTANCES_DIR}/instance-1/config/openclaw.json" 2>/dev/null || echo "")
  env_token=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "${INSTANCES_DIR}/instance-1/.env" | cut -d= -f2)
  # At minimum the .env token must be a 64-char hex string
  [[ "$env_token" =~ ^[0-9a-f]{64}$ ]]
}

@test "cluster_restore fails when backup file is missing" {
  run cluster_restore "/nonexistent/path/backup.tar.gz" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no encontrado"* ]]
}

@test "cluster_restore renames extracted dir if id differs" {
  # Make a tarball of instance-1
  cluster_backup 1 >/dev/null
  tarball=$(ls -1 "${TEST_TMPDIR}/backups/"*.tar.gz | head -n1)
  rm -rf "${INSTANCES_DIR}"
  mkdir -p "${INSTANCES_DIR}"

  # Restore as id=2: should create instance-2/ even though tarball has instance-1/
  cluster_restore "$tarball" 2 >/dev/null
  [ -d "${INSTANCES_DIR}/instance-2" ]
  [ ! -d "${INSTANCES_DIR}/instance-1" ]
}
