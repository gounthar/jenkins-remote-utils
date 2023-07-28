#!/bin/bash

function make_jenkins_api_request() {
  local api_endpoint=$1

  # Ensure there is no trailing '/' at the end of JENKINS_URL
  JENKINS_URL=$(echo "$JENKINS_URL" | sed 's#/$##')

  # Ensure there are no slashes at the beginning of api_endpoint
  api_endpoint=$(echo "$api_endpoint" | sed 's#^/##')

  # Now, concatenate the two parts
  url="${JENKINS_URL}/${api_endpoint}"
  # Use the updated URL with curl
  curl -s -k -u "$USERNAME:$API_TOKEN" "$url"

  html_message "[${FUNCNAME[0]}] URL: $url"
  # html_message "$(curl -s -k -u "$USERNAME:$API_TOKEN" "$url")"

  # curl -s -k -u $USERNAME:$API_TOKEN "${JENKINS_URL}${api_endpoint}"
}

JENKINS_CREDENTIALS="$USERNAME:$PASSWORD"

function waiting_for_services_to_be_ready() {
  # Ensure there is no trailing '/' at the end of JENKINS_URL
  JENKINS_LOGIN_URL=$(echo "$JENKINS_URL" | sed 's#/$##')/login

  # After the curl request, the output is piped to the awk command. It is used to search for the message
  # "Please wait while Jenkins is getting ready to work" in the curl output.
  # If the message is found, awk exits with a non-zero status (1), and the loop continues.
  # If the message is not found, the loop exits, and the "Jenkins is running" message is displayed.
  timeout 60 bash -c "until curl -s -f $JENKINS_LOGIN_URL > /dev/null; do sleep 5; done" && standard_message "Jenkins is running" || standard_message "Jenkins is not running"
  standard_message "Jenkins is ready"
  JENKINS_VERSION=$(curl -s -I -k "$JENKINS_URL" | grep -i '^X-Jenkins:' | awk '{print $2}')
  standard_message "Jenkins version is: $JENKINS_VERSION"
}

# Before launching a job, we need to create a token for the admin user
function create_api_token() {
  # The first part of this script will extract the protocol, hostname, port, and trailing slash (if present) from the
  # JENKINS_URL. Then, it will extract the username and password from the JENKINS_CREDENTIALS variable.
  # Finally, it will construct the new URL by combining the extracted information.
  # Note: The following  script assumes that the JENKINS_CREDENTIALS variable contains the username and password
  # separated by a colon (:).
  # Parse the protocol, hostname, and port from the JENKINS_URL
  # using regex capture groups
  [[ $JENKINS_URL =~ ^(https?)://([^/]+)(:[0-9]+)?(/)?$ ]]
  protocol="${BASH_REMATCH[1]}"
  hostname="${BASH_REMATCH[2]}"
  port="${BASH_REMATCH[3]}"
  trailing_slash="${BASH_REMATCH[4]}"

  # Extract username and password from JENKINS_CREDENTIALS
  username=$(echo "$JENKINS_CREDENTIALS" | cut -d':' -f1)
  password=$(echo "$JENKINS_CREDENTIALS" | cut -d':' -f2)

  # Reconstruct the new URL with username and password
  if [[ -n "$port" ]]; then
    # URL with a specified port
    new_url="$protocol://$username:$password@$hostname$port$trailing_slash"
  else
    # URL without a specified port
    new_url="$protocol://$username:$password@$hostname$trailing_slash"
  fi

  debug_message "Original URL: $JENKINS_URL"
  debug_message "New URL: $new_url"

  concatenate=concat\(//crumbRequestField,%22:%22,//crumb\)
  JENKINS_CRUMB_URL="$(echo "$new_url" | sed 's#/$##')/crumbIssuer/api/xml?xpath=$concatenate"
  debug_message "JENKINS_CRUMB_URL: $JENKINS_CRUMB_URL"
  CRUMB=$(curl -s -k $JENKINS_CRUMB_URL -c cookies.txt)
  debug_message "CRUMB was found: $CRUMB"
  JENKINS_TOKEN_URL="$(echo "$new_url" | sed 's#/$##')/user/admin/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken"
  debug_message "JENKINS_TOKEN_URL: $JENKINS_TOKEN_URL"
  TOKEN=$(curl -s -k "$JENKINS_TOKEN_URL" --data 'newTokenName=kb-token' -b cookies.txt -H $CRUMB | jq -r '.data.tokenValue')
  debug_message "TOKEN was found: $TOKEN"
}

