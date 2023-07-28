#!/bin/bash

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

# Source the REST API utility functions from jenkins_api_utils.sh
source ./jenkins_api_utils.sh

# Source the job-related functions from jenkins_jobs.sh
source ./jenkins_jobs.sh

# Associative arrays to store agent usage count and last used timestamp
declare -A agent_usage_count
declare -A agent_last_used_timestamp

function get_defined_agents() {
  local agents_response
  agents_response=$(make_jenkins_api_request "/computer/api/json")

  # Parse the agent names and store them in the associative arrays
  local agent_names
  agent_names=$(echo "$agents_response" | jq -r '.computer[] | select(.displayName != null) | .displayName')

  # Initialize the agent usage count and last used timestamp
  for agent_name in $agent_names; do
    if [ -z "${agent_usage_count["$agent_name"]}" ]; then
      agent_usage_count["$agent_name"]=0
    fi
    if [ -z "${agent_last_used_timestamp["$agent_name"]}" ]; then
      agent_last_used_timestamp["$agent_name"]=0
    fi
  done
}

function is_agent_active() {
  local agent=$1
  local api_endpoint="/computer/$agent/api/json"
  local agent_info
  agent_info=$(make_jenkins_api_request "$api_endpoint")

  # Check if the agent exists and is not offline
  if [ -n "$agent_info" ]; then
    local offline
    offline=$(echo "$agent_info" | jq -r '.offline')
    [ "$offline" = "false" ]
  else
    false
  fi
}

function normalize_agent_name() {
  local agent_name="$1"

  # Remove any unwanted characters or labels
  agent_name=$(echo "$agent_name" | sed -E 's/\[Label:.*\]//')

  # Trim leading/trailing whitespaces and tabs
  agent_name=$(echo "$agent_name" | sed -E 's/^[ \t]+|[ \t]+$//')

  echo "$agent_name"
}

function get_agents_for_builds() {
  local builds="$1"

  # Create associative arrays to store agent information
  declare -A agent_usage_count
  declare -A agent_last_used_timestamp

   # Loop through each build in the builds array
    for build in "${builds[@]}"; do
      local console_output=$(get_console_output_for_build "$build")

      # Use awk to process the console output and extract agent information
      awk -v RS='\nRunning on ' -F '\n' '
        function normalize_agent_name(agent_name) {
          gsub(/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/, "", agent_name);  # Remove ANSI color codes
          gsub(/^\s+|\s+$/, "", agent_name);  # Trim leading/trailing whitespaces
          return agent_name;
        }

        NF > 1 {
          gsub(/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/, "", $0);  # Remove ANSI color codes
          agent_name = $1;
          agent_name = normalize_agent_name(agent_name);  # Normalize the agent name
          for (i = 2; i <= NF; i++) {
            if ($i ~ /^[0-9]+ [0-9]+ [0-9]+:[0-9]+:[0-9]+$/) {
              agent_last_used_timestamp[agent_name] = $i " " $(i-1);
              break;
            }
          }
          agent_usage_count[agent_name]++;
        }
      ' <<< "$console_output"
    done

  # Pass the agent information to the calling function using global variables
  AGENT_USAGE_COUNT=("${agent_usage_count[@]}")
  AGENT_LAST_USED_TIMESTAMP=("${agent_last_used_timestamp[@]}")
}

# Sort agents by usage count and last used timestamp
function sort_agents() {

  print_subtitle "Sorted Agents:"

  sorted_agents=()

  # Loop through each agent in the associative array
  for agent in "${!agent_usage_count[@]}"; do
    # Extract usage count and last used timestamp
    usage_count=${agent_usage_count[$agent]}
    last_used=${agent_last_used_timestamp[$agent]}

    # Format the last used timestamp to a sortable format (YYYYMMDD HH:MM:SS)
    # timestamp=$(date -d "$last_used" "+%Y%m%d %H:%M:%S")
    timestamp=$last_used

    # Append agent details to the array for sorting
    sorted_agents+=("$agent,$usage_count,$timestamp")
  done

  # Sort the array by usage count (descending) and last used timestamp (ascending)
  IFS=$'\n' sorted_agents=($(sort -t',' -k2,2nr -k3,3 <<<"${sorted_agents[*]}"))
  unset IFS

  # Print the sorted agents
  for agent_info in "${sorted_agents[@]}"; do
    IFS=',' read -r agent usage_count timestamp <<< "$agent_info"
    echo "Agent: $agent"
    echo "Usage Count: $usage_count"
    echo "Last Used Timestamp: $timestamp"
    echo
  done
}

function get_agents_for_builds_works() {
  local job_name=$1
  local last_10_builds=$2 # used to be ($(get_last_10_build_numbers_for_job "$job_name"))

  debug_message "[${FUNCNAME[0]}] Getting console output for job: $job_name, builds: $last_10_builds"

  for build_number in "${last_10_builds[@]}"; do
    local api_endpoint="/job/$job_name/$build_number/consoleText"

    debug_message "[${FUNCNAME[0]}] Getting console output for job: $job_name, build: $build_number"

    local console_output
    console_output=$(make_jenkins_api_request "$api_endpoint")
    if [ -n "$console_output" ]; then
      debug_message "[${FUNCNAME[0]}] Job: $job_name, Build: $build_number"
      local agent_info
      agent_info=$(extract_agent_info_from_console <(echo "$console_output"))
      debug_message "[${FUNCNAME[0]}] Agent: $agent_info"
      debug_message "[${FUNCNAME[0]}] --------------"

      # Update the agent usage count
      if [ -n "$agent_info" ]; then
        if [ -z "${agent_usage_count["$agent_info"]}" ]; then
          agent_usage_count["$agent_info"]=1
        else
          ((agent_usage_count["$agent_info"]++))
        fi

        # Update the last used timestamp
        local build_timestamp
        build_timestamp=$(get_build_timestamp "$job_name" "$build_number")
        if [ -n "$build_timestamp" ]; then
          if [ -z "${agent_last_used_timestamp["$agent_info"]}" ] || [ "$build_timestamp" -gt "${agent_last_used_timestamp["$agent_info"]}" ]; then
            agent_last_used_timestamp["$agent_info"]=$build_timestamp
          fi
        fi
      fi
    else
      debug_message "[${FUNCNAME[0]}] Error: Unable to retrieve console output for job: $job_name, build: $build_number" >&2
    fi
  done
}

# Function to display the found agents
function display_agents() {
  local total_agents=0

  for agent_name in "${!agent_usage_count[@]}"; do
    local usage_count=${agent_usage_count["$agent_name"]}
    local last_used_timestamp=${agent_last_used_timestamp["$agent_name"]}
    echo "Agent: $agent_name"
    debug_message "Agent: $agent_name"
    #echo "Usage Count: $usage_count"
    #echo "Last Used Timestamp: $last_used_timestamp"
    #echo
    ((total_agents++))
  done

  echo "Total Agents: $total_agents"
  echo
}

function display_agents_summary() {
  # Display the summary of agents found
  print_subtitle "Agent Summary:"
  for agent_info in "${!agent_usage_count[@]}"; do
    echo "Agent: $agent_info"
    echo "Usage Count: ${agent_usage_count["$agent_info"]}"
    debug_message "Agent: $agent_info"
    debug_message "Usage Count: ${agent_usage_count["$agent_info"]}"

    # Check if the timestamp is valid and non-empty
    if [[ -n "${agent_last_used_timestamp["$agent_info"]}" && "${agent_last_used_timestamp["$agent_info"]}" != "N/A" ]]; then
      # Convert Unix timestamp to human-readable date format using date command
      local last_used_date
      last_used_date="${agent_last_used_timestamp["$agent_info"]}"
      echo "Last Used Timestamp: $last_used_date"
      debug_message "Last Used Timestamp: $last_used_date"
    else
      echo "Last Used Timestamp: N/A"
      debug_message "Last Used Timestamp: N/A"
    fi

    echo
  done

  # Display the size of the associative array
  echo "Total Agents: ${#agent_usage_count[@]}"
  debug_message "Total Agents: ${#agent_usage_count[@]}"
}
