#!/bin/bash

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

# Source the job-related functions from jenkins_jobs.sh
source ./jenkins_jobs.sh

# Associative arrays to store agent usage count and last used timestamp
declare -A agent_usage_count
declare -A agent_last_used_timestamp

function get_defined_agents() {
  local api_endpoint="/computer/api/json?pretty=true"
  local defined_agents
  defined_agents=$(make_jenkins_api_request "$api_endpoint" | jq -r '.computer | .[].displayName')
  info_message "$defined_agents"
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

function get_agents_for_builds() {
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

function display_agents_summary() {
  # Display the summary of agents found
  print_subtitle "Agent Summary:"
  for agent_info in "${!agent_usage_count[@]}"; do
    echo "Agent: $agent_info"
    echo "Usage Count: ${agent_usage_count["$agent_info"]}"
    echo "Last Used Timestamp: ${agent_last_used_timestamp["$agent_info"]}"
    echo
  done
}
