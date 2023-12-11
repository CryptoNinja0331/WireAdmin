#!/usr/bin/env bash
set -e

TOR_CONFIG="/etc/tor/torrc"
ENV_FILE="/app/.env"

remove_duplicated_lines() {
  local file="$1"
  local temp_file="/tmp/$(basename "$file")"
  awk '!seen[$0]++' "$file" >"$temp_file"
  mv "$temp_file" "$file"
}

remove_duplicate_env() {
  local file="$1"
  local temp_file="/tmp/$(basename "$file")"
  awk -F "=" -e '!seen[$1]++' "$file" >"$temp_file"
  mv "$temp_file" "$file"
}

to_camel_case() {
  echo "${1}" | awk -F_ '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1' OFS=""
}

mkdir -p /var/vlogs

if [ ! -f "${ENV_FILE}" ]; then
  echo "" >"${ENV_FILE}"
fi

chmod 400 "${ENV_FILE}"

if ! grep -q "AUTH_SECRET" "${ENV_FILE}"; then
  cat "${ENV_FILE}" &>/dev/null <<EOF
AUTH_SECRET=$(openssl rand -base64 32)
EOF
fi

# Checking if there is `UI_PASSWORD` environment variable
# if there was, converting it to hex and storing it to
# the .env
if [ -n "$UI_PASSWORD" ]; then
  ui_password_hex=$(echo -n "$UI_PASSWORD" | xxd -ps -u)
  sed -e '/^HASHED_PASSWORD=/d' "${ENV_FILE}"
  cat "${ENV_FILE}" &>/dev/null <<EOF
HASHED_PASSWORD=$ui_password_hex
EOF
  unset UI_PASSWORD
fi

remove_duplicate_env "${ENV_FILE}"

# IP address of the container
inet_address="$(hostname -i | awk '{print $1}')"

sed -i "s/{{INET_ADDRESS}}/$inet_address/g" "${TOR_CONFIG}"

# any other environment variables that start with TOR_ are added to the torrc
# file
env | grep ^TOR_ | sed -e 's/TOR_//' -e 's/=/ /' | while read -r line; do
  key=$(echo "$line" | awk '{print $1}')
  value=$(echo "$line" | awk '{print $2}')
  key=$(to_camel_case "$key")
  echo "$key $value" >>"${TOR_CONFIG}"
done

# Removing duplicated lines form "${TOR_CONFIG}" file
remove_duplicated_lines "${TOR_CONFIG}"

# Checking if there is /etc/torrc.d folder and if there is
# any file in it, adding them to the torrc file
TORRC_DIR_FILES=$(find /etc/torrc.d -type f -name "*.conf")
if [ -n "$TORRC_DIR_FILES" ]; then
  for file in $TORRC_DIR_FILES; do
    cat "$file" >>"${TOR_CONFIG}"
  done
fi

# Remove comment line with single Hash
sed -i '/^#\([^#]\)/d' "${TOR_CONFIG}"
# Remove options with no value. (KEY[:space:]{...VALUE})
sed -i '/^[^ ]* $/d' "${TOR_CONFIG}"
# Remove double empty lines
sed -i '/^$/N;/^\n$/D' "${TOR_CONFIG}"

# Start Tor on the background
screen -L -Logfile /var/vlogs/tor -dmS tor \
  bash -c "tor -f ${TOR_CONFIG}"

# Starting Redis server in detached mode
screen -L -Logfile /var/vlogs/redis -dmS redis \
  bash -c "redis-server --port 6479 --daemonize no --dir /data --appendonly yes"

echo "                                                   "
echo " _       ___           ___       __          _     "
echo "| |     / (_)_______  /   | ____/ /___ ___  (_)___ "
echo "| | /| / / / ___/ _ \/ /| |/ __  / __ \`__ \/ / __ \\"
echo "| |/ |/ / / /  /  __/ ___ / /_/ / / / / / / / / / /"
echo "|__/|__/_/_/   \___/_/  |_\__,_/_/ /_/ /_/_/_/ /_/ "
echo "                                                   "

sleep 1
echo -e "\n======================== Versions ========================"
echo -e "Alpine Version: \c" && cat /etc/alpine-release
echo -e "WireGuard Version: \c" && wg -v | head -n 1 | awk '{print $1,$2}'
echo -e "Tor Version: \c" && tor --version | head -n 1
echo -e "Obfs4proxy Version: \c" && obfs4proxy -version
echo -e "\n========================= Torrc ========================="
cat "${TOR_CONFIG}"
echo -e "========================================================\n"
sleep 1

screen -L -Logfile /var/vlogs/warmup -dmS warmup \
  bash -c "sleep 10; echo -n '[+] Warming Up...'; curl -s http://127.0.0.1:3000/; echo -e 'Done!'"

exec "$@"
