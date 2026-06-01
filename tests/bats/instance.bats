#!/usr/bin/env bats
# tests/bats/instance.bats — instance naming and port computation.

setup() {
  load helpers/load
  export BASE_PORT=18000
}

@test "instance_gateway_port id=1 returns 18022" {
  result=$(instance_gateway_port 1)
  [ "$result" = "18022" ]
}

@test "instance_gateway_port id=0 returns 18000" {
  result=$(instance_gateway_port 0)
  [ "$result" = "18000" ]
}

@test "instance_gateway_port id=5 returns 18110" {
  result=$(instance_gateway_port 5)
  [ "$result" = "18110" ]
}

@test "instance_bridge_port is gateway+1" {
  gid=$(instance_gateway_port 7)
  bid=$(instance_bridge_port 7)
  [ "$((bid - gid))" = "1" ]
}

@test "instance_name produces instance-<id>" {
  result=$(instance_name 12)
  [ "$result" = "instance-12" ]
}

@test "instance_dir uses default root" {
  result=$(instance_dir 3)
  [ "$result" = "./instances/instance-3" ]
}

@test "instance_dir honors custom root" {
  result=$(instance_dir 3 /tmp/data)
  [ "$result" = "/tmp/data/instance-3" ]
}

@test "ports are unique across ids" {
  seen=""
  for i in 1 2 3 4 5; do
    p=$(instance_gateway_port "$i")
    if [[ " $seen " == *" $p "* ]]; then
      echo "duplicate port $p"
      return 1
    fi
    seen="$seen $p"
  done
}

@test "no port collision between gateway and bridge" {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    g=$(instance_gateway_port "$i")
    b=$(instance_bridge_port "$i")
    [ "$g" != "$b" ] || { echo "collision at $i"; return 1; }
  done
}
