#!/bin/sh
# Print a T3 Code login link.  Usage: ./pair.sh [ttl]   e.g. ./pair.sh 30d
cd "$(dirname "$0")" && exec docker compose exec t3code t3-pair "$@"
