#!/usr/bin/env bash
set -o errexit -o pipefail -o noclobber -o nounset

logfile=$(pwd)/run-dev.log

run_env=DEV

# Via https://stackoverflow.com/a/14203146/4168713 (M2)
opts=$(getopt -l 'verbose,dry-run,telepresence,help' -o 'vzth' -n "$0" -- "$@")
telepresence_enabled=no
verbose=no
dry_run=no
eval set -- "$opts"
while true; do
  case "$1" in
    -v|--verbose)
      verbose=yes
      shift
      ;;
    -z|--dry-run)
      dry_run=yes
      shift
      ;;
    -t|--telepresence)
      telepresence_enabled=yes
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTION]..."
      echo "Starts a Scynet cluster using minikube, and optionally connects to it via telepresence."
      echo ""
      echo "Options:"
      echo "  -t, --telepresence         start telepresence after configuring the cluster"
      echo "  -v, --verbose              show commands being run and their output"
      echo "  -z, --dry-run              only check if all dependencies are present, do nothing else"
      echo "  -h, --help                 show this help page"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "[ BUG] Failed to parse arguments"
      exit 3
      ;;
  esac
done

source run-common.sh

function main {
  set_process "starting development environment"; echo
  needed="minikube kubectl sbt docker "
  if [ $telepresence_enabled != no ]; then
    needed+="telepresence "
  fi
  ensure_intalled $needed
  ensure_submodules
  if [ $dry_run != no ]; then
    echo_ok "finished checking dependencies"
  else
    start_cluster
    start_kafka
    start_kafka_additions
    start_parity
    build_harvester
    start_harvester
    echo_ok "finished starting the development environment"
    if [ $telepresence_enabled != no ]; then
      run_telepresence
    fi
  fi
}

trap handle_exit EXIT
rm -f $logfile
main
trap - EXIT
