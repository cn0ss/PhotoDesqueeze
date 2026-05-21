#!/usr/bin/env bash
set -euo pipefail

TIMEOUT="${CODESIGN_TIMESTAMP_TIMEOUT:-5m}"
RETRIES="${CODESIGN_TIMESTAMP_RETRIES:-3}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

duration_to_seconds() {
  local duration="$1"
  local suffix="${duration: -1}"
  local number="$duration"
  local multiplier=1

  case "$suffix" in
    s)
      number="${duration%s}"
      multiplier=1
      ;;
    m)
      number="${duration%m}"
      multiplier=60
      ;;
    h)
      number="${duration%h}"
      multiplier=3600
      ;;
  esac

  [[ "$number" =~ ^[0-9]+$ ]] || die "Invalid timeout duration: $duration"
  printf '%s\n' "$((number * multiplier))"
}

run_with_timeout() {
  local seconds="$1"
  shift

  perl -MPOSIX -e '
    use strict;
    use warnings;

    my $timeout = shift @ARGV;
    die "missing timeout\n" unless defined $timeout && $timeout =~ /^\d+$/;
    die "missing command\n" unless @ARGV;

    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) {
      exec @ARGV or die "exec failed: $!\n";
    }

    my $deadline = time() + $timeout;
    while (1) {
      my $done = waitpid($pid, POSIX::WNOHANG());
      if ($done == $pid) {
        my $status = $?;
        exit(128 + ($status & 127)) if ($status & 127);
        exit($status >> 8);
      }
      if (time() >= $deadline) {
        kill "TERM", $pid;
        sleep 2;
        kill "KILL", $pid;
        waitpid($pid, 0);
        exit 124;
      }
      sleep 1;
    }
  ' "$seconds" "$@"
}

[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "Invalid retry count: $RETRIES"
[[ "$RETRIES" -gt 0 ]] || die "Retry count must be greater than zero"
[[ "$#" -gt 0 ]] || die "Usage: Scripts/codesign-with-timeout.sh codesign [args...]"

TIMEOUT_SECONDS="$(duration_to_seconds "$TIMEOUT")"

for ((attempt = 1; attempt <= RETRIES; attempt++)); do
  printf 'Running codesign attempt %d/%d with timeout %s\n' "$attempt" "$RETRIES" "$TIMEOUT" >&2
  if run_with_timeout "$TIMEOUT_SECONDS" "$@"; then
    exit 0
  else
    status="$?"
  fi

  if [[ "$status" -ne 124 ]]; then
    exit "$status"
  fi

  printf 'codesign timed out after %s\n' "$TIMEOUT" >&2
done

die "codesign did not finish after $RETRIES attempts"
