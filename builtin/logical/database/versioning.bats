#!/usr/bin/env bats

#################################################################################
# Full end-to-end tests of the Vault binary with v4 and v5 Database interfaces. #
#                                                                               #
# To run these tests, you need the following:                                   #
# - bats installed (https://github.com/bats-core/bats-core)                     #
# - Vault binary to test against                                                #
# - mock-v4-database-plugin built (plugins/database/mockv4/)                    #
# - mock-v5-database-plugin built (plugins/database/mockv5/)                    #
# - Path to Vault binary updated below (if needed)                              #
# - Path to database plugins updated below (if needed)                          #
#                                                                               #
# NOTE: These tests have been run on MacOS. There's a good                      #
#       chance something not work if run on Linux                               #
#################################################################################

# Directory where the Vault binary is located
path_to_vault="$HOME/go/bin"

# Location of mock-v4-database-plugin and mock-v5-database-plugin
plugin_dir="$HOME/dev/vault/plugins/"

# Debugging output for the tests themselves
logfile="test.log"

# Update the PATH so it knows how to run the vault binary
PATH="${PATH}:${path_to_vault}"

# Explicitly set the VAULT_ADDR
VAULT_ADDR="http://127.0.0.1:8200"

setup() {
  run vault status -address=${VAULT_ADDR};
  [ $status -ne 0 ] # Vault appears to already be running

  truncate ${logfile}

  echo "$(date) - Starting Vault" >> ${logfile}

  vault server -dev -dev-plugin-dir="${plugin_dir}" &

  # Wait for Vault to become available
  echo "$(date) - Waiting for vault to become available..." >> ${logfile}
  run vault status -address=${VAULT_ADDR};
  while [ "$status" -ne 0 ]; do
    sleep 1
    run vault status -address=${VAULT_ADDR}
  done
  sleep 1

  echo "$(date) - Vault is available - enabling database engine..." >> ${logfile}
  vault secrets enable -address=${VAULT_ADDR} database
  echo "$(date) - Beginning test" >> ${logfile}
}

teardown() {
  echo "$(date) - Shutting down Vault" >> ${logfile}

  pkill vault

  echo "$(date) - Checking if any database plugins are still running..." >> ${logfile}
  run ps -ef | grep "mock-v4-database-plugin" | grep -v "grep"
  [ $status -ne 0 ]
  run ps -ef | grep "mock-v5-database-plugin" | grep -v "grep"
  [ $status -ne 0 ]

  echo "$(date) - Test complete" >> ${logfile}
}

getTTL() {
  run curl -s --header "X-Vault-Token: $(vault token lookup -format=json | jq -r .data.id)" \
      --request PUT \
      --data "{\"lease_id\":\"${lease_id}\"}" \
      $VAULT_ADDR/v1/sys/leases/lookup
  [ $status -eq 0 ] # Ensure the curl command didn't fail

  local ttl=$(echo "${output}" | jq -r .data.ttl)
  if [[ ${ttl} == "" || ${ttl} == "null" ]]; then
    echo -1
  else
    echo ${ttl}
  fi
}

waitUntilTTL() {
  while [ true ]; do
    local ttl=$(getTTL)
    echo "$(date) - Checking TTL... ${ttl}" >> ${logfile}
    if [ ${ttl} -lt $1 ]; then
      break
    fi
    sleep 0.5
  done
}

waitUntilExpired() {
  while [ true ]; do
    local ttl=$(getTTL)
    echo "$(date) - Checking if expired... ${ttl}" >> ${logfile}
    if [ ${ttl} -lt 0 ]; then
      break
    fi
    sleep 0.5
  done
}

run_test() {
  dbname="$1"
  plugin_name="$2"
  policy_name="$3"
  password_regex="$4"

  if [ "${password_regex}" == "" ]; then
    password_regex="."
  fi

  role_name="${dbname-role}"
  static_role="${role_name}-static"
  static_username="${static_role}-user"
  default_ttl=5
  max_ttl=10m

  echo "$(date) - password assertion: '${password_regex}'" >> ${logfile}

  # Configure
  echo "$(date) - Configuring..." >> ${logfile}
  run vault write -address=${VAULT_ADDR} \
    "database/config/${dbname}" \
    plugin_name="${plugin_name}" \
    'connection_url=mock://{{username}}:{{password}}@mock' \
    username=mockuser \
    password=somepassword \
    allowed_roles='*' \
    password_policy="${policy_name}"
  [ $status -eq 0 ]

  # Rotate root credentials
  echo "$(date) - Rotating root creds..." >> ${logfile}
  run vault write -address=${VAULT_ADDR} \
    -force \
    "database/rotate-root/${dbname}"
  [ $status -eq 0 ]

  # Create a role
  echo "$(date) - Creating role..." >> ${logfile}
  run vault write -address=${VAULT_ADDR} \
    "database/roles/${role_name}" \
    db_name="${dbname}" \
    default_ttl="${default_ttl}s" \
    max_ttl=1m
  [ $status -eq 0 ]

  # Get credentials for role
  echo "$(date) - Getting credentials for role..." >> ${logfile}
  run vault read -address=${VAULT_ADDR} \
    -format=json \
    "database/creds/${role_name}"
  [ $status -eq 0 ]
  password=$(echo "${output}" | jq -r .data.password)
  echo "$(date) - Password: ${password} Regex: ${password_regex}" >> ${logfile}
  [[ "${password}" =~ $password_regex ]]

  lease_id=$(echo "${output}" | jq -r .lease_id)
  echo "$(date) - Lease ID: ${lease_id}" >> ${logfile}

  # Check status of lease - ensure the lease is less than ${default_ttl}-1
  wait_until=$(expr ${default_ttl} - 1)
  waitUntilTTL ${wait_until}

  # Renew lease
  echo "$(date) - Renewing lease..." >> ${logfile}
  run vault lease renew -address=${VAULT_ADDR} \
    ${lease_id}
  [ $status -eq 0 ]

  # Ensure the TTL was refreshed
  ttl=$(getTTL)
  [ ${ttl} -ge ${wait_until} ]

  # Force expiration of the lease
  echo "$(date) - Revoking lease..." >> ${logfile}
  run vault lease revoke -address=${VAULT_ADDR} \
    ${lease_id}
  [ $status -eq 0 ]

  # Ensure the lease no longer exists
  echo "$(date) - Making sure lease no longer exists..." >> ${logfile}
  ttl=$(getTTL)
  echo "$(date) - TTL: ${ttl}" >> ${logfile}
  [ ${ttl} -eq -1 ]

  # Static credentials
  echo "$(date) - Creating static role..." >> ${logfile}
  run vault write -address=${VAULT_ADDR} \
    database/static-roles/${static_role} \
    db_name=${dbname} \
    username="${static_username}" \
    rotation_period=${default_ttl}
  [ $status -eq 0 ]

  echo "$(date) - Reading static creds..." >> ${logfile}
  run vault read -address=${VAULT_ADDR} \
    -format=json \
    database/static-creds/${static_role}
  [ $status -eq 0 ]
  old_password=$(echo "${output}" | jq -r .data.password)
  password="${old_password}"
  [[ "${password}" =~ $password_regex ]]

  ttl=$(echo "${output}" | jq -r .data.ttl)

  cur_time=$(date +%s)
  max_time=$(expr ${cur_time} + 10)
  echo "$(date) - Waiting for static creds refresh... (cur time: ${cur_time} max time: ${max_time})" >> ${logfile}

  while [ true ]; do
    run vault read -address=${VAULT_ADDR} \
      -format=json \
      database/static-creds/${static_role}
    [ $status -eq 0 ]

    new_password=$(echo "${output}" | jq -r .data.password)
    password="${new_password}"
    [[ "${password}" =~ $password_regex ]]

    if [ "${new_password}" != "${old_password}" ]; then
      break
    fi
    cur_time=$(date +%s)
    [ ${cur_time} -le ${max_time} ] # Timed out waiting for new creds
    sleep 1
  done
}

@test "v4 database without password policies" {
  run_test \
    "mockdbv4" \
    "mock-v4-database-plugin" \
    "" \
    "[[ \"\${password}\" =~ ^password_[0-9]{4}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]-[0-9][0-9]:[0-9][0-9]$ ]]"
}

@test "v4 database with password policies" {
  # Create policy - this will be ignored since this is using DB v4
  raw_policy='length = 20

rule "charset" {
	charset = "abcdeABCDE01234💩"
}

rule "charset" {
	charset = "💩"
	min-chars = 1
}
'

  vault write sys/policies/password/emoji_policy policy="${raw_policy}"

  run_test \
    "mockdbv4" \
    "mock-v4-database-plugin" \
    "emoji_policy" \
    "[[ ! \"\${password}\" =~ 💩 ]]"
}

@test "v5 database without password policies" {
  run_test \
    "mockdbv5" \
    "mock-v5-database-plugin" \
    "" \
    "[[ \"\${password}\" =~ ^[a-zA-Z0-9-]+$ ]]"
}


@test "v5 database with password policies" {
  # Create policy to be used
  raw_policy='length = 20

rule "charset" {
	charset = "abcdeABCDE01234💩"
}

rule "charset" {
	charset = "💩"
	min-chars = 1
}
'

  vault write sys/policies/password/emoji_policy policy="${raw_policy}"

  run_test \
    "mockdbv5" \
    "mock-v5-database-plugin" \
    "emoji_policy" \
    "[[ \"\${password}\" =~ 💩 ]]"
}
