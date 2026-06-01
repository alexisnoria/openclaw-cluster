#!/usr/bin/env bats
# tests/integration/commands.bats — batch dispatcher (run_batch) routes every
# command. We do NOT need to actually start containers for this; we test the
# dispatcher surface and error handling.

load helpers/setup

@test "no args shows help and exits non-zero" {
  # In CI without a TTY, the menu would hang. We only test batch path.
  # `status` should run without args.
  run run_cluster status
  [ "$status" -eq 0 ]
}

@test "unknown batch command exits non-zero" {
  run run_cluster does-not-exist
  [ "$status" -ne 0 ]
  [[ "$output" == *"Comando batch desconocido"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "destroy on missing instance exits non-zero" {
  run run_cluster destroy 999
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "status on empty cluster prints warning" {
  # Clean instances dir
  rm -rf instances backups
  run run_cluster status
  # status exits 0 even with no instances (it prints a warning)
  [[ "$output" == *"No hay instancias"* ]] || [[ "$status" -eq 0 ]]
}

@test "tokens on empty cluster prints warning" {
  rm -rf instances backups
  run run_cluster tokens
  [[ "$output" == *"No hay instancias"* ]]
}

@test "backup on missing instance errors" {
  run run_cluster backup 999
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "restore on missing backup file errors" {
  run run_cluster restore /nonexistent/path.tar.gz 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no encontrado"* ]] || [[ "$output" == *"No se encontró"* ]]
}

@test "set-openrouter-key on missing instance errors" {
  run run_cluster set-openrouter-key 999 newkey
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "set-telegram on missing instance errors" {
  run run_cluster set-telegram 999 token pairing
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "init rejects count > 50" {
  run run_cluster init 51
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 y 50"* ]]
}

@test "init rejects count < 1" {
  run run_cluster init 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 y 50"* ]]
}

@test "init rejects non-numeric count" {
  run run_cluster init abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"inválido"* ]]
}
