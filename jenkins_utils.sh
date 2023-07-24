#!/bin/bash

# Colors
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
NC='\e[0m'  # No Color

# Function to print a debug message in red
# Parameters:
# $1: The debug message to print
function debug_message() {
  local message="$1"
  echo -e "\e[1;31m[DEBUG]\e[0m $message\e[0m" >>"$TEMP_DEBUG_FILE"
}

function info_message() {
  local message="$1"
  echo -e "\e[1;33m[INFO]\e[0m $message\e[0m"
}

function error_message() {
  local message="$1"
  echo -e "\e[1;91m[ERROR]\e[0m $message\e[0m" >>"$TEMP_DEBUG_FILE"
}

function standard_message() {
  local message="$1"
  echo -e "\e[1;32m[MESSAGE]\e[0m $message\e[0m" >>"$TEMP_DEBUG_FILE"
  echo -e "\e[1;32m[MESSAGE] $message\e[0m"
}

# Function to display HTML results in blue
html_message() {
  local message="$1"
  echo -e "${BLUE}[HTML] ${message}${NC}" >>"$TEMP_DEBUG_FILE"
}

# Function to display the contents of an associative array in a human-readable format
display_associative_array() {
  local array_name="$1"
  local -n arr="$2"  # Take the name of the associative array as a reference

  if [[ ${#arr[@]} -eq 0 ]]; then
    standard_message "$array_name is an empty associative array."
    return
  fi

  standard_message "Associative array \"$array_name\" contents:"
  for key in "${!arr[@]}"; do
    standard_message "Key: $key, Value: ${arr[$key]}"
  done
}

info_message "TEMP_DEBUG_FILE: $TEMP_DEBUG_FILE"

function print_title() {
  local title_text=$1
  echo -e "\e[44m\e[97m$title_text\e[0m"
  debug_message "\e[44m\e[97m$title_text\e[0m"
}

function print_subtitle() {
  local subtitle_text=$1
  echo -e "\n\e[1m\e[104m\e[97m$subtitle_text\e[0m"
  debug_message "\n\e[1m\e[104m\e[97m$subtitle_text\e[0m"
}

function print_subsubtitle() {
  local subtitle_text=$1
  echo -e "\e[96m$subtitle_text\e[0m"
  debug_message "\e[96m$subtitle_text\e[0m"
}

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

function convert_timestamp_to_date() {
  local timestamp=$1
  if [ -n "$timestamp" ]; then
    date -d "@$((timestamp / 1000))" +"%Y-%m-%d %H:%M:%S"
  else
    echo "Unknown Timestamp"
  fi
}
