#!/bin/sh
set -eu

# If /config/server.cfg exists it becomes the authoritative configuration.
# Otherwise Portainer environment variables are used on each restart.
# The engine only reads configs from its registered storage roots, never
# from absolute /config paths. Put generated/manual configs in $USERDIR.
userdir="${XDG_DATA_HOME:-/config/data}/teeworlds"
mkdir -p "$userdir"
if [ -f /config/server.cfg ]; then
  cp /config/server.cfg "$userdir/.custom-server.cfg"
  exec ./teeworlds_srv -f .custom-server.cfg "$@"
fi

config="$userdir/.generated-server.cfg"

# Quotes a Teeworlds string value, avoiding multiline console injection.
quote_value() {
  printf '%s' "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g'
}
integer() {
  key=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) echo "Invalid numeric setting: $key" >&2; exit 2 ;;
  esac
  printf '%s %s\n' "$key" "$value" >> "$config"
}
string() {
  key=$1
  value=$2
  printf '%s "%s"\n' "$key" "$(quote_value "$value")" >> "$config"
}

: > "$config"
string sv_name "${TW_SERVER_NAME:-Teeworlds Bots}"
integer sv_port 8303
integer sv_register "${TW_PUBLIC:-0}"
string sv_map "${TW_MAP:-dm1}"
string sv_gametype "${TW_GAME_TYPE:-dm}"
integer sv_max_clients "${TW_MAX_CLIENTS:-16}"
integer sv_player_slots "${TW_PLAYER_SLOTS:-12}"
integer sv_bot_slots "${TW_BOT_SLOTS:-4}"
integer sv_bot_always_enable "${TW_BOT_ALWAYS_ENABLE:-2}"
integer sv_bot_allow_move "${TW_BOT_ALLOW_MOVE:-1}"
integer sv_bot_allow_fire "${TW_BOT_ALLOW_FIRE:-1}"
integer sv_bot_allow_hook "${TW_BOT_ALLOW_HOOK:-1}"
integer sv_bot_accuracy "${TW_BOT_ACCURACY:-1}"
if [ -n "${TW_RCON_PASSWORD:-}" ]; then
  string sv_rcon_password "$TW_RCON_PASSWORD"
fi

exec ./teeworlds_srv -f .generated-server.cfg "$@"
