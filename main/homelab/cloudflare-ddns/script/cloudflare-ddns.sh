#!/usr/bin/env sh

findCurrentIP() {
  printf "Finding current ip\n"
  ip4=$(curl -s https://ipv4.icanhazip.com/)
  printf "Current External IP is %s" "$ip4"
  printf "\n"
}

checkAndUpdateIP() {
  printf "Updating ip for the CF Record %s \n" "$1"
  record4=$(
    curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONEID/dns_records?name=$1&type=A" \
      -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
      -H "X-Auth-Key: $CLOUDFLARE_APIKEY" \
      -H "Content-Type: application/json"
  )

  old_ip4=$(echo "$record4" | sed -n 's/.*"content":"\([^"]*\).*/\1/p')
  if [ "$ip4" = "$old_ip4" ]; then
    printf "%s - Success - IP Address '%s' has not changed yet\n" "$(date -u)" "$ip4"
    return 0
  fi

  record4_identifier=$(echo "$record4" | sed -n 's/.*"id":"\([^"]*\).*/\1/p')
  update4=$(
    curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONEID/dns_records/$record4_identifier" \
      -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
      -H "X-Auth-Key: $CLOUDFLARE_APIKEY" \
      -H "Content-Type: application/json" \
      --data "{\"id\":\"$CLOUDFLARE_ZONEID\",\"type\":\"A\",\"name\":\"$1\",\"content\":\"$ip4\"}"
  )

  if echo "$update4" | grep -q '\"success\":false'; then
    printf "%s - Yikes - Updating IP Address '%s' has failed" "$(date -u)" "$ip4"
    exit 1
  else
    printf "%s - Success - IP Address '%s' has been updated\n" "$(date -u)" "$ip4"
  fi
}

set -o nounset
set -o errexit

findCurrentIP
checkAndUpdateIP "$CLOUDFLARE_RECORD_NAME_1"
checkAndUpdateIP "$CLOUDFLARE_RECORD_NAME_2"
checkAndUpdateIP "$CLOUDFLARE_RECORD_NAME_3"
