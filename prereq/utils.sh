
set +x
set -e
set -o pipefail

# Logging functions and ASCII color helpers.
COLOR_RESET=$'\e[0m'
COLOR_GREEN=$'\e[32m'
COLOR_RED=$'\e[31m'

log_success() {
  echo "${COLOR_GREEN}✅ $*${COLOR_RESET}"
}

log_error() {
  echo "${COLOR_RED}❌ $*${COLOR_RESET}" >&2
}
