#! /usr/bin/env bash

set -eE -u -o pipefail
shopt -s inherit_errexit

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d)"
readonly ROOT WORKDIR
trap 'rm -rf "${WORKDIR}"' EXIT

fail() {
  printf 'check_render: %s\n' "${*}" >&2
  exit 1
}

copy_template() {
  local dest="${1}"
  shift

  copier copy --vcs-ref=HEAD --defaults --quiet "${@}" "${ROOT}" "${dest}" \
    || fail "copier copy failed for ${dest}"
}

assert_file() {
  local path="${1}"
  [[ -f "${path}" ]] || fail "missing file ${path}"
}

assert_contains() {
  local path="${1}"
  local needle="${2}"
  grep -Fq "${needle}" "${path}" || fail "${path} does not contain: ${needle}"
}

assert_absent() {
  local path="${1}"
  [[ ! -e "${path}" ]] || fail "unexpected path ${path}"
}

# GitHub + Rust + devcontainer
copy_template "${WORKDIR}/github-rust" \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license=MIT \
  --data project_copyright_holder='Georg Lauterbach' \
  --data lang_python_enabled=false \
  --data lang_rust_enabled=true \
  --data lang_shell_enabled=false \
  --data lang_container_enabled=false \
  --data git_ecosystem=github \
  --data git_ecosystem_username=georglauterbach \
  --data dev_container_enabled=true \
  --data dev_container_use_hermes=true \
  --data code_binary_enabled=true \
  --data code_library_enabled=true

# shellcheck disable=SC2016
assert_contains "${WORKDIR}/github-rust/AGENTS.md" '`.github/`'
assert_file "${WORKDIR}/github-rust/src/main.rs"
assert_file "${WORKDIR}/github-rust/src/lib.rs"
assert_contains "${WORKDIR}/github-rust/Cargo.toml" 'repository = "https://github.com/georglauterbach/demo"'
assert_contains "${WORKDIR}/github-rust/Cargo.toml" 'license = "MIT"'

python3 - "${WORKDIR}/github-rust/.devcontainer/devcontainer.json" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
json.loads(text)
PY

python3 - "${WORKDIR}/github-rust" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
text = (root / '.github' / 'dependabot.yml').read_text(encoding='utf-8')
marker = 'package-ecosystem: cargo'
idx = text.find(marker)
if idx < 0:
    raise SystemExit('cargo ecosystem missing from dependabot.yml')
chunk = text[idx:idx + 200]
directory_line = next(
    line.strip() for line in chunk.splitlines() if line.strip().startswith('directory:')
)
directory = directory_line.split(':', 1)[1].strip()
resolved = (root / directory.lstrip('/')).resolve() if directory != '/' else root.resolve()
manifest = resolved / 'Cargo.toml'
if not manifest.is_file():
    raise SystemExit(f'cargo directory {directory!r} has no Cargo.toml')
PY

# POSIX sh
copy_template "${WORKDIR}/shell-sh" \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license= \
  --data lang_python_enabled=false \
  --data lang_rust_enabled=false \
  --data lang_shell_enabled=true \
  --data lang_shell_type=sh \
  --data lang_container_enabled=false \
  --data git_ecosystem= \
  --data dev_container_enabled=false

assert_contains "${WORKDIR}/shell-sh/.editorconfig" 'shell_variant            = posix'
assert_contains "${WORKDIR}/shell-sh/.gitattributes" '*.sh    text'
assert_contains "${WORKDIR}/shell-sh/.shellcheckrc" 'shell=sh'

# fish: no ShellCheck config
copy_template "${WORKDIR}/shell-fish" \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license= \
  --data lang_python_enabled=false \
  --data lang_rust_enabled=false \
  --data lang_shell_enabled=true \
  --data lang_shell_type=fish \
  --data lang_container_enabled=false \
  --data git_ecosystem= \
  --data dev_container_enabled=false

assert_absent "${WORKDIR}/shell-fish/.shellcheckrc"
assert_contains "${WORKDIR}/shell-fish/.gitattributes" '*.sh    text'

# Rust without a license
copy_template "${WORKDIR}/rust-no-license" \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license= \
  --data lang_python_enabled=false \
  --data lang_rust_enabled=true \
  --data lang_shell_enabled=false \
  --data lang_container_enabled=false \
  --data git_ecosystem= \
  --data dev_container_enabled=false \
  --data code_binary_enabled=true \
  --data code_library_enabled=false

assert_file "${WORKDIR}/rust-no-license/src/main.rs"
assert_absent "${WORKDIR}/rust-no-license/src/lib.rs"
grep -q '^license' "${WORKDIR}/rust-no-license/Cargo.toml" \
  && fail 'empty license key should be omitted from Cargo.toml'

# Python: no Rust questions, still renders
copy_template "${WORKDIR}/python" \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license= \
  --data lang_python_enabled=true \
  --data lang_rust_enabled=false \
  --data lang_shell_enabled=false \
  --data lang_container_enabled=false \
  --data git_ecosystem= \
  --data dev_container_enabled=false

# shellcheck disable=SC2016
assert_contains "${WORKDIR}/python/AGENTS.md" '`README.md`'
assert_absent "${WORKDIR}/python/Cargo.toml"

# Neither binary nor library is rejected
if copier copy --vcs-ref=HEAD --defaults --quiet \
  --data project_name=demo \
  --data project_description='A demo project' \
  --data project_license= \
  --data lang_python_enabled=false \
  --data lang_rust_enabled=true \
  --data lang_shell_enabled=false \
  --data lang_container_enabled=false \
  --data git_ecosystem= \
  --data dev_container_enabled=false \
  --data code_binary_enabled=false \
  --data code_library_enabled=false \
  "${ROOT}" "${WORKDIR}/rust-none" 2>"${WORKDIR}/rust-none.err"
then
  fail 'expected copier to reject a Rust project with neither binary nor library'
fi

printf 'check_render: ok\n'
