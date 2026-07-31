#!/usr/bin/env bash
# stackctl — Docker Compose stack management tool
# https://github.com/RAW-Network/homelab
# (c) 2024-2026 RAW-Network. All rights reserved
set -uo pipefail


# Environment setup


# Resolve the directory where this script is located (follows symlinks).
resolve_root() {
  local src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    local dir; dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"; [[ "$src" != /* ]] && src="$dir/$src"
  done
  ROOT="$(cd -P "$(dirname "$src")" && pwd)"
}

# Ensure a UTF-8 locale is active for unicode status symbols.
force_utf8_locale() {
  case "${LC_ALL:-${LANG:-}}" in *UTF-8*|*utf8*) return 0;; esac
  if command -v locale >/dev/null 2>&1; then
    if locale -a 2>/dev/null | grep -qi '^C\.UTF-8$'; then export LC_ALL=C.UTF-8 LANG=C.UTF-8
    elif locale -a 2>/dev/null | grep -qi '^en_US\.UTF-8$'; then export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    fi
  fi
}

# Detect docker compose binary (v2 plugin or standalone).
detect_compose() {
  if [[ -n "${COMPOSE_BIN:-}" ]]; then read -r -a COMPOSE_CMD <<< "$COMPOSE_BIN"
  else
    if docker compose version >/dev/null 2>&1; then COMPOSE_CMD=(docker compose)
    elif docker-compose version >/dev/null 2>&1; then COMPOSE_CMD=(docker-compose)
    else { printf '%s\n' "Compose not found. Install Docker Compose."; exit 1; }; fi
  fi
}


# Helpers


tolower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
relpath() { local p="$1"; printf '%s' "${p#"$ROOT"/}"; }


# Discovery & status


# Find all compose files under ROOT.
discover_all() {
  mapfile -t COMPOSE_FILES < <(find "$ROOT" -type f \( -iname 'compose.yaml' -o -iname 'compose.yml' -o -iname 'docker-compose.yaml' -o -iname 'docker-compose.yml' \) 2>/dev/null | sort)
}

unicode_ok() { case "${LC_ALL:-${LANG:-}}" in *UTF-8*|*utf8*) return 0;; *) return 1;; esac; }

# Initialize status indicator symbols (unicode or ascii fallback).
init_symbols() {
  if unicode_ok && printf '\xe2\x97\x8f' | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    DOT_GREEN=$'\033[32m\u25CF\033[0m'
    DOT_RED=$'\033[31m\u25CF\033[0m'
  else
    DOT_GREEN=$'\033[32mo\033[0m'
    DOT_RED=$'\033[31mx\033[0m'
  fi
}

# Calculate max column width for aligned output.
calc_width_name() {
  local name="$1"; local -n arr="$name"; local max=3
  local cf d len
  for cf in "${arr[@]}"; do d="$(relpath "$(dirname "$cf")")"; len=${#d}; (( len>max )) && max=$len; done
  (( max < 3 )) && max=3
  printf '%d' "$max"
}

# Return green/red dot based on container state.
status_symbol_for() {
  local cf="$1" running exited
  if command -v timeout >/dev/null 2>&1; then
    running="$(timeout 2 "${COMPOSE_CMD[@]}" -f "$cf" ps -q --status running 2>/dev/null | wc -l | tr -d ' ')"
    exited="$(timeout 2 "${COMPOSE_CMD[@]}" -f "$cf" ps -q --status exited 2>/dev/null | wc -l | tr -d ' ')"
  else
    running="$("${COMPOSE_CMD[@]}" -f "$cf" ps -q --status running 2>/dev/null | wc -l | tr -d ' ')"
    exited="$("${COMPOSE_CMD[@]}" -f "$cf" ps -q --status exited 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [[ "${running:-0}" -gt 0 ]]; then printf '%s' "$DOT_GREEN"
  elif [[ "${exited:-0}" -gt 0 ]]; then printf '%s' "$DOT_RED"
  else printf ' '; fi
}


# Spinner & parallel status cache


declare -A STATUS_CACHE

start_spinner() {
  local total="$1" markdir="$2"
  (
    local i=0; local spin='|/-\'
    while :; do
      local donec; donec="$(ls "$markdir"/*.ok 2>/dev/null | wc -l | tr -d ' ')"
      (( donec > total )) && donec="$total"
      local pct=$(( total>0 ? donec*100/total : 100 ))
      printf '\rScanning stacks: %3d%% [%c] %d/%d' "$pct" "${spin:i%4:1}" "$donec" "$total"
      (( donec >= total )) && break
      i=$((i+1))
      sleep 0.1
    done
    printf '\n'
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]]; then wait "$SPINNER_PID" 2>/dev/null || true; unset SPINNER_PID; fi
}

# Query status for all stacks in parallel (STAT_WORKERS, default 8).
ensure_status_cache_parallel() {
  local name="$1"; local -n arr="$name"
  STATUS_CACHE=()
  local total="${#arr[@]}"
  local tmpdir; tmpdir="$(mktemp -d)"
  start_spinner "$total" "$tmpdir"
  local workers="${STAT_WORKERS:-8}"
  local i=0 cf
  for cf in "${arr[@]}"; do
    i=$((i+1))
    (
      local s; s="$(status_symbol_for "$cf")"
      printf '%s' "$s" > "$tmpdir/$i.sym"
      printf '%s' "$cf" > "$tmpdir/$i.path"
      : > "$tmpdir/$i.ok"
    ) &
    while (( $(jobs -r | wc -l) >= workers )); do wait -n || true; done
  done
  wait || true
  stop_spinner
  local f idx path sym
  for f in "$tmpdir"/*.path; do
    [[ -e "$f" ]] || continue
    idx="${f##*/}"; idx="${idx%.path}"
    path="$(cat "$f")"
    sym="$(cat "$tmpdir/$idx.sym" 2>/dev/null || printf ' ')"
    STATUS_CACHE["$path"]="$sym"
  done
  rm -rf "$tmpdir"
}


# Display


# Print all discovered stacks with status indicators.
list_available() {
  local name="$1"; local -n arr="$name"
  ensure_status_cache_parallel "$name"
  local w; w="$(calc_width_name "$name")"
  printf " 0) %-*s   %s  ->  %s\n" "$w" "ALL" " " "Deploy All Stacks"
  local i=1 cf d f s
  for cf in "${arr[@]}"; do
    d="$(relpath "$(dirname "$cf")")"; f="$(basename "$cf")"; s="${STATUS_CACHE[$cf]:- }"
    printf "%2d) %-*s   %s  ->  %s\n" "$i" "$w" "$d" "$s" "$f"
    i=$((i+1))
  done
}

# Print selected stacks.
list_selected() {
  local name="$1"; local -n arr="$name"
  local w; w="$(calc_width_name "$name")"
  local i=1 cf d f s
  for cf in "${arr[@]}"; do
    d="$(relpath "$(dirname "$cf")")"; f="$(basename "$cf")"; s="${STATUS_CACHE[$cf]:- }"
    printf "%2d) %-*s   %s  ->  %s\n" "$i" "$w" "$d" "$s" "$f"
    i=$((i+1))
  done
}


# Selection parser — supports indices, keywords, and "0" for all


unique_append() { local outname="$1"; local item="$2"; local -n out="$outname"; local x; for x in "${out[@]:-}"; do [[ "$x" == "$item" ]] && return; done; out+=("$item"); }

select_by_tokens() {
  local tokens="$1"; local poolname="$2"; local outname="$3"
  local -n pool="$poolname"; local -n out="$outname"; out=()
  local cleaned; cleaned="$(echo "$tokens" | tr -d '[:space:]')"
  IFS=',' read -r -a toks <<< "$cleaned"
  local n="${#pool[@]}" t
  for t in "${toks[@]}"; do
    [[ -z "$t" ]] && continue
    if [[ "$t" == "0" ]]; then out=("${pool[@]}"); return
    elif [[ "$t" =~ ^[0-9]+$ ]]; then (( t>=1 && t<=n )) && unique_append "$outname" "${pool[$((t-1))]}"
    else
      local kwl; kwl="$(tolower "$t")"
      local cf d base dlow blow
      for cf in "${pool[@]}"; do
        d="$(dirname "$cf")"; base="$(basename "$d")"; dlow="$(tolower "$d")"; blow="$(tolower "$base")"
        [[ "$blow" == *"$kwl"* || "$dlow" == *"$kwl"* ]] && unique_append "$outname" "$cf"
      done
    fi
  done
}


# Stack actions — deploy, update, stop


# Print progress bar.
print_header() {
  local done="$1" total="$2" action="$3" target="$4"
  local pct=0; (( total>0 )) && pct=$(( done*100/total ))
  local width=28; local fill=$(( pct*width/100 ))
  local bar; bar="$(printf "%${fill}s" "" | tr ' ' '#')"; bar="${bar}$(printf "%$((width-fill))s" "" | tr ' ' '-')"
  printf "[%2d/%2d] %3d%% |%-s| %s: %s\n" "$done" "$total" "$pct" "$bar" "$action" "$target"
}

# Start containers.
deploy_file() {
  local cf="$1" start end; start="$(date +%s)"
  if "${COMPOSE_CMD[@]}" -f "$cf" up -d; then end="$(date +%s)"; printf 'Deploy OK (%s) in %ss\n' "$(relpath "$(dirname "$cf")")" "$((end-start))"; return 0
  else end="$(date +%s)"; printf 'Deploy FAILED (%s) in %ss\n' "$(relpath "$(dirname "$cf")")" "$((end-start))"; return 1; fi
}

# Pull latest images and recreate containers.
update_file() {
  local cf="$1" start end
  printf 'Pulling images for %s ...\n' "$(relpath "$(dirname "$cf")")"
  "${COMPOSE_CMD[@]}" -f "$cf" pull || true
  start="$(date +%s)"
  if "${COMPOSE_CMD[@]}" -f "$cf" up -d --force-recreate --remove-orphans; then end="$(date +%s)"; printf 'Update OK (%s) in %ss\n' "$(relpath "$(dirname "$cf")")" "$((end-start))"; return 0
  else end="$(date +%s)"; printf 'Update FAILED (%s) in %ss\n' "$(relpath "$(dirname "$cf")")" "$((end-start))"; return 1; fi
}

# Stop and remove containers.
stop_file() {
  local cf="$1"
  local have; have="$("${COMPOSE_CMD[@]}" -f "$cf" ps -q --all 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${have:-0}" -eq 0 ]]; then printf 'Stop FAILED (%s): no containers found\n' "$(relpath "$(dirname "$cf")")"; return 1; fi
  if "${COMPOSE_CMD[@]}" -f "$cf" down; then printf 'Stop OK (%s)\n' "$(relpath "$(dirname "$cf")")"; return 0
  else printf 'Stop FAILED (%s)\n' "$(relpath "$(dirname "$cf")")"; return 1; fi
}


# User input


confirm() {
  local prompt="$1" ans
  if [[ -r /dev/tty ]]; then read -r -p "$prompt [y/N]: " ans < /dev/tty; else read -r -p "$prompt [y/N]: " ans; fi
  case "${ans,,}" in y|yes) return 0;; *) return 1;; esac
}

prompt_line() {
  local prompt="$1" out
  if [[ -r /dev/tty ]] ; then read -r -p "$prompt" out < /dev/tty; else read -r -p "$prompt" out; fi
  printf '%s' "$out"
}


# Bulk execution — run action on selected stacks with progress


run_bulk() {
  local action="$1"; shift
  local -a targets=("$@")
  local n ok err done tstart tend tdur cf tgt
  n=${#targets[@]}; ok=0; err=0; done=0; tstart=$(date +%s)
  for cf in "${targets[@]}"; do
    done=$((done+1)); tgt="$(relpath "$(dirname "$cf")")"
    print_header "$((done-1))" "$n" "$action" "$tgt"
    if "$action"_file "$cf"; then ok=$((ok+1)); else err=$((err+1)); fi
  done
  tend=$(date +%s); tdur=$((tend - tstart))
  print_header "$done" "$n" "completed" "-"
  printf 'Summary: OK=%s ERRORS=%s Duration=%ss\n' "$ok" "$err" "$tdur"
  if (( err>0 )); then return 1; else return 0; fi
}


# Interactive flow


# Discover stacks, show list, prompt selection, execute action.
do_action_with_selection() {
  local action="$1"
  discover_all
  ((${#COMPOSE_FILES[@]})) || { printf '%s\n' "No stacks found."; return 0; }
  printf 'Directory: %s\n' "$ROOT"
  printf 'Available stacks (%d):\n' "${#COMPOSE_FILES[@]}"
  list_available COMPOSE_FILES
  local sel; sel="$(prompt_line 'Enter selection (0=ALL, indices/keywords, comma separated): ')"
  [[ -n "${sel:-}" ]] || { printf '%s\n' "Empty selection."; return 0; }
  local MATCHED=()
  select_by_tokens "$sel" COMPOSE_FILES MATCHED
  ((${#MATCHED[@]})) || { printf '%s\n' "No stacks matched."; return 0; }
  printf 'Selected stacks (%d):\n' "${#MATCHED[@]}"
  list_selected MATCHED
  if confirm "Proceed to $action"; then run_bulk "$action" "${MATCHED[@]}"; else printf '%s\n' "Aborted"; fi
}

# Main menu loop.
menu() {
  while true; do
    printf 'Directory: %s\n' "$ROOT"
    printf '%s\n' "1) DEPLOY STACK"
    printf '%s\n' "2) UPDATE STACK"
    printf '%s\n' "3) STOP STACK"
    printf '%s\n' "4) EXIT"
    local choice; choice="$(prompt_line 'Choose an option [1-4]: ')"
    case "$choice" in
      1) do_action_with_selection deploy ;;
      2) do_action_with_selection update ;;
      3) do_action_with_selection stop ;;
      4) printf '%s\n' "See you next time!"; printf '%s\n' "(c) 2024-2026 RAW-Network. All rights reserved"; exit 0 ;;
      *) printf '%s\n' "Invalid choice" ;;
    esac
    read -r -p "Press Enter to return to menu..." _ < /dev/tty || true
    printf '\n'
  done
}


# Entrypoint


resolve_root
force_utf8_locale
detect_compose
init_symbols
menu
