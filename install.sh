#!/usr/bin/env bash
# Linux installer (Windows users: run Install.bat instead).
exec "$(dirname "${BASH_SOURCE[0]}")/linux/install.sh" "$@"
