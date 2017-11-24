#!/bin/bash

set -e

# Get the first domain of a comma separated list.
function get_base_domain {
  awk -F ',' '{print $1}' <(echo ${1:?}) | tr -d ' '
}
export -f get_base_domain

# Run a letsencrypt-nginx-proxy-companion container
function run_le_container {
  local image="${1:?}"
  local name="${2:?}"
  docker run -d \
    --name "$name" \
    --volumes-from $NGINX_CONTAINER_NAME \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --add-host boulder:${BOULDER_IP} \
    --env "DEBUG=true" \
    --env "ACME_CA_URI=http://${BOULDER_IP}:4000/directory" \
    --label letsencrypt-companion \
    "$image" > /dev/null && echo "Started letsencrypt container for test ${name%%_2*}"
}
export -f run_le_container

# Wait for the /etc/nginx/certs/dhparam.pem file to exist in container $1
function wait_for_dhparam {
  local name="${1:?}"
  local i=0
  sleep 1
  echo -n "Waiting for the $name container to generate a DH parameters file, this might take a while..."
  until docker exec "$name" [ -f /etc/nginx/certs/dhparam.pem ]; do
    if [ $i -gt 600 ]; then
      echo "DH parameters file was not generated under ten minutes by the $name container, timing out."
      exit 1
    fi
    i=$((i + 5))
    sleep 5
  done
  echo "Done."
}
export -f wait_for_dhparam

# Wait for the /etc/nginx/certs/$1/cert.pem file to exist inside container $2
function wait_for_cert {
  local domain="${1:?}"
  local name="${2:?}"
  local i=0
  until docker exec "$name" [ -f /etc/nginx/certs/$domain/cert.pem ]; do
    if [ $i -gt 180 ]; then
      echo "Certificate for $domain was not generated under three minutes, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Certificate for $domain has been generated."
}
export -f wait_for_cert

# Wait for a successful https connection to domain $1
function wait_for_conn {
  local domain="${1:?}"
  local i=0
  until curl -k https://"$domain" > /dev/null 2>&1; do
    if [ $i -gt 120 ]; then
      echo "Could not connect to $domain using https under two minutes, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Connection to $domain using https was successful."
}
export -f wait_for_conn
