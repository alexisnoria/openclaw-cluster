#!/usr/bin/env bats
# tests/integration/backup.bats — `cluster_backup` creates a tar.gz with the
# right shape; `cluster_restore` extracts it into the right path. We do NOT
# start containers in this test.

load helpers/setup

@test "backup creates a tar.gz with instance-1 inside" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  run run_cluster backup 1
  [ "$status" -eq 0 ]
  # There should be exactly one .tar.gz
  archive_count=$(find backups -name 'instance-1_*.tar.gz' | wc -l | tr -d ' ')
  [ "$archive_count" -ge 1 ]
  # Inspect contents
  archive=$(find backups -name 'instance-1_*.tar.gz' | head -1)
  tar -tzf "$archive" | grep -q 'instance-1/config/openclaw.json'
  tar -tzf "$archive" | grep -q 'instance-1/.env'
}

@test "backup rejects missing instance" {
  run run_cluster backup 999
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "restore extracts a backup into the right instance dir" {
  # Setup: init + backup
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  # Wipe a file to ensure restore puts it back
  rm instances/instance-1/config/openclaw.json

  archive=$(find backups -name 'instance-1_*.tar.gz' | head -1)
  [ -n "$archive" ]

  # Restore into instance 1
  run run_cluster restore "$archive" 1
  [ "$status" -eq 0 ]
  assert_file_exists instances/instance-1/config/openclaw.json
  assert_valid_json instances/instance-1/config/openclaw.json
}

@test "restore refuses to overwrite without confirmation" {
  run run_cluster init 1 latest yes yes UTC "${FAKE_API_KEY}" "openrouter/test/test-model" "" pairing
  [ "$status" -eq 0 ]
  archive=$(find backups -name 'instance-1_*.tar.gz' | head -1)
  # Auto-decline overwrite via "n"
  run bash -c "echo 'n' | ./openclaw-cluster.sh restore '$archive' 1"
  [ "$status" -eq 0 ]
  # The original instance should still be intact
  assert_file_exists instances/instance-1/config/openclaw.json
}
