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

# Discover maps from the image, including any future additions to data/maps.
# Never interpret map filenames as console commands.
all_maps=""
for map_path in data/maps/*.map; do
  [ -f "$map_path" ] || continue
  map_name=${map_path##*/}
  map_name=${map_name%.map}
  case "$map_name" in
    ''|*[!A-Za-z0-9_-]*) continue ;;
  esac
  all_maps="${all_maps:+$all_maps }$map_name"
done

[ -n "$all_maps" ] || { echo "No maps found in data/maps" >&2; exit 1; }

# 'all' follows all packaged maps automatically; empty disables rotation
# or player choices, and a space-separated list selects individual maps.
map_rotation=${TW_MAP_ROTATION-all}
[ "$map_rotation" = all ] && map_rotation=$all_maps
vote_maps=${TW_VOTE_MAPS-all}
[ "$vote_maps" = all ] && vote_maps=$all_maps

: > "$config"
string sv_name "${TW_SERVER_NAME:-Teeworlds Bots}"
integer sv_port 8303
integer sv_register "${TW_PUBLIC:-0}"
string sv_map "${TW_MAP:-dm1}"
string sv_maprotation "$map_rotation"
integer sv_matches_per_map "${TW_MATCHES_PER_MAP:-1}"
integer sv_timelimit "${TW_TIME_LIMIT:-0}"
integer sv_scorelimit "${TW_SCORE_LIMIT:-20}"
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

# Add every configured map as a built-in player vote option.
# The game accepts: add_vote "description" "change_map mapname".
for map_name in $vote_maps; do
  case "$map_name" in
    ''|*[!A-Za-z0-9_-]*) continue ;;
  esac
  [ -f "data/maps/$map_name.map" ] || continue
  printf 'add_vote "Map %s" "change_map %s"\n' "$map_name" "$map_name" >> "$config"
done

exec ./teeworlds_srv -f .generated-server.cfg "$@"
