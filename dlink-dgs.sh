#!/usr/bin/env bash

usage() {
  echo "Usage: $0 ARGS ACTION PARAMS"
  echo
  echo "Arguments:"
  echo "  -u, --username     Username (admin)"
  echo "  -p, --password     Password"
  echo "  -H, --host         Hostname"
  echo "  -P, --port         Port (80)"
  echo "  -T, --tls          Use HTTPS"
  echo
  echo "Actions:"
  echo "  poe PORT STATE     Set POE state (PORT: 1-24, STATE: on|off)"
  echo "  poe [status]       Get current POE states"
}

echo_info() {
  # bold and blue
  echo -e "\033[1;34m$*\033[0m" >&2
}

echo_error() {
  # bold and red
  echo -e "\033[1;31m$*\033[0m" >&2
}

# FIXME Reverse-engineer this crappy obfuscated JS code to generate the MD5 hash
jsmd5() {
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  {
    local suffix="http"
    # cat mm.js
    curl -fsSL "$API_URL/js/mm.js" 2>/dev/null
    echo "; console.log(md5('${1}_${suffix}'));"
  } | node

  # NOTE Alternative that's also awkward
  # node md5-weird.js \
  #   --host "$SWITCH_HOSTNAME" \
  #   --port "$PORT" \
  #   ${USE_HTTPS:+--https} \
  #   --username "$USERNAME" \
  #   --password "$PASSWORD" \
  #   "$@"
}

curl_api() {
  local host="$SWITCH_HOSTNAME"
  local port="$PORT"
  local username="$USERNAME"
  local password="$PASSWORD"

  password_hash="$(jsmd5 "$password")"

  curl -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-raw "key=&username=${username}&password=${password_hash}" \
    "http${USE_HTTPS:+s}://${host}:${port}/goform/SetLogin"
}

login() {
  local host="$SWITCH_HOSTNAME"
  local port="$PORT"
  local username="$USERNAME"
  local password="$PASSWORD"

  password_hash="$(jsmd5 "$password")"

  # NOTE A successful login ends with "Empty reply from server"
  # -> if we get a 200 that's a login failure
  if curl -L -X POST -c "$COOKIE_JAR" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-raw "key=&username=${username}&password=${password_hash}" \
    "${API_URL}/goform/SetLogin" 2>/dev/null
  then
    cat "$COOKIE_JAR"
    echo "Login failed" >&2
    return 1
  fi

  return 0
}

poe_action() {
  local poe_port="${1:-12}" # port 12 by default
  local poe_state="${2:-1}" # 1: on, 0: off
  local poe_state_human_readable

  if [[ ! $poe_port =~ ^[0-9]+$ ]]
  then
    echo_error "Invalid POE port number: $poe_port"
    return 2
  fi

  case "$poe_state" in
    on|enable|1)
      poe_state=1
      poe_state_human_readable="ON"
      ;;
    off|disable|0)
      poe_state=0
      poe_state_human_readable="OFF"
      ;;
  esac

  if [[ ! "$poe_state" =~ ^[01]$ ]]
  then
    echo_error "Invalid POE port state: $poe_state"
    return 2
  fi

  echo_info "Setting POE port $poe_port to $poe_state_human_readable"

  curl -X POST \
    -b "$COOKIE_JAR" \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-raw "hidAction=0&hidDelProfile=0&max_flag=0&from_port=${poe_port}&to_port=${poe_port}&priority=3&poeState=${poe_state}&select_max_wattage=0&profilename=None" \
    "${API_URL}/goform/SetPortPoe"
}

poe_state() {
  # FIXME This is a mess, but it works
  # TODO remove the jsonrepair dependency
  curl -fsSL -b "$COOKIE_JAR" \
    "${API_URL}/system/poe/366_poe_setting.asp" | \
    awk '/^ +poe_setting =/{flag=1; next} /;/{flag=0} flag' | \
    jsonrepair | \
    jq -n '[input[] | {(.[0]): (.[1] == "Enabled")} ] | add'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  # Default values
  USERNAME="${USERNAME:-admin}"
  PORT="${PORT:-80}"

  COOKIE_JAR="$(mktemp)"
  trap 'rm -f "$COOKIE_JAR"' EXIT

  while [[ "$#" -gt 0 ]]
  do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      -u|--username)
        USERNAME="$2"
        shift 2
        ;;
      -p|--password)
        PASSWORD="$2"
        shift 2
        ;;
      -H|--host*)
        SWITCH_HOSTNAME="$2"
        shift 2
        ;;
      -P|--port)
        PORT="$2"
        shift 2
        ;;
      -T|--tls|--ssl|--https)
        USE_HTTPS=1
        # Only override port if it's the default
        if [[ "$PORT" == 80 ]]
        then
          PORT=443
        fi
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "$USERNAME" ]]
  then
    echo_error "Username is required"
    exit 2
  fi

  if [[ -z "$PASSWORD" ]]
  then
    echo_error "Password is required"
    exit 2
  fi

  if [[ -z "$SWITCH_HOSTNAME" ]]
  then
    echo_error "Hostname is required"
    exit 2
  fi

  API_URL="http${USE_HTTPS:+s}://${SWITCH_HOSTNAME}:${PORT}"

  case "$1" in
    help|--help)
      usage
      exit 0
      ;;
    poe)
      shift
      login
      if [[ "$#" -eq 0 ]] || [[ "$1" =~ ^(status|state)$ ]]
      then
        poe_state
        exit "$?"
      fi

      poe_action "$@"
      ;;
    *)
      echo_error "Unknown action: $1"
      usage >&2
      exit 2
      ;;
  esac
fi
