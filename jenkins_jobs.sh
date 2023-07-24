#!/bin/bash

function get_all_jobs() {
  local api_endpoint="/api/json"
  local all_jobs
  all_jobs=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$all_jobs" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve job information from Jenkins API."
    return
  fi

  all_jobs=$(echo "$all_jobs" | jq -r '.jobs | .[].url' | awk -F'/' '{print $(NF-1)}')
  echo "$all_jobs"
}

function get_last_build_number_for_job() {
  local job_name=$1
  local api_endpoint="/job/$job_name/lastBuild/api/json"
  local last_build_info
  last_build_info=$(make_jenkins_api_request "$api_endpoint")
  local build_number
  build_number=$(echo "$last_build_info" | jq -r '.number')
  echo "$build_number"
}

function is_freestyle_job() {
  local job_name=$1
  local api_endpoint="/job/$job_name/api/json"
  local job_info
  job_info=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
    return
  fi

  # Check if the job is a freestyle job
  local job_class
  job_class=$(echo "$job_info" | jq -r '._class')
  [ "$job_class" = "hudson.model.FreeStyleProject" ]
}

function is_pipeline_job() {
  local job_name=$1
  local api_endpoint="/job/$job_name/api/json"
  local job_info
  job_info=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
    return
  fi

  # Check if the job is a pipeline job
  local job_class
  job_class=$(echo "$job_info" | jq -r '._class')
  [ "$job_class" = "org.jenkinsci.plugins.workflow.job.WorkflowJob" ]
}

function is_multibranch_job() {
  # set -x
  local job_name=$1
  local api_endpoint="/job/$job_name/api/json"
  local job_info
  job_info=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
    return
  fi

  # Check if the job is a multibranch pipeline
  local job_class
  job_class=$(echo "$job_info" | jq -r '._class')
  [ "$job_class" = "org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" ]
}

function get_multibranch_pipeline_jobs() {
  local api_endpoint="/api/json"
  local all_jobs
  all_jobs=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$all_jobs" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve job information from Jenkins API."
    return
  fi

  all_jobs=$(echo "$all_jobs" | jq -r '.jobs | .[].url' | awk -F'/' '{print $(NF-1)}')

  # Filter only the multi-branch pipeline jobs
  local multibranch_jobs
  while read -r job; do
    if is_multibranch_job "$job"; then
      multibranch_jobs+=" $job"
    fi
  done <<<"$all_jobs"

  echo "$multibranch_jobs"
}

function get_valid_multibranch_jobs() {
  local job_name=$1
  local api_endpoint="/job/$job_name/api/json"
  local job_info
  job_info=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
    return
  fi

  # Get valid multibranch jobs for the given job_name
  local multibranch_jobs
  multibranch_jobs=$(echo "$job_info" | jq -r '.jobs[] | select(.color != "disabled") | .url')
  echo "$multibranch_jobs"
}

function get_last_build_numbers_for_job() {
  local job_url=${1//$JENKINS_URL/}
  local api_endpoint="api/json"
  local job_info
  job_info=$(make_jenkins_api_request "/job/$job_url/$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_url using /job/$job_url/$api_endpoint"
    return
  fi

  # Debug: Output the API response for the job
  #    echo "API Response for job $job_url:"
  #    echo "$job_info"

  # Get the last 10 build numbers for the job
  local builds_info
  builds_info=$(echo "$job_info" | jq -r '.builds | map(.number) | join(" ")' | tail -n 10)
  echo "Builds Info:"
  echo "$builds_info" | tail -n 10
}

function get_last_10_build_numbers_for_job() {
  local job_url=$1

  debug_message "[${FUNCNAME[0]}] Preparing for job: $job_url"

  # Remove any trailing slashes from the job_url
  job_url=$(echo "$job_url" | sed 's#/$##')

  # Check if the job_url starts with '/job/'
  if [[ "$job_url" != "/job/"* ]]; then
    job_url="/job/$job_url"
  fi

  local api_endpoint="api/json"
  local job_info
  debug_message "[${FUNCNAME[0]}] Getting last 10 build numbers for job: $job_url/$api_endpoint"
  job_info=$(make_jenkins_api_request "$job_url/$api_endpoint")

  if [ -z "$job_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_url using $job_url/$api_endpoint"
    return
  fi

  # Get the last 10 build numbers for the job
  local builds_info
  builds_info=$(echo "$job_info" | jq -r '.builds | map(.number) | join(" ")' | tail -n 10)
  echo "Builds Info:"
  echo "$builds_info" | tail -n 10

}

function get_build_timestamp() {
  local job_name=$1
  local build_number=$2
  local api_endpoint="/job/$job_name/$build_number/api/json?pretty=true"
  local build_info
  build_info=$(make_jenkins_api_request "$api_endpoint")

  if [ -z "$build_info" ]; then
    error_message "[${FUNCNAME[0]}] Error: Unable to retrieve build information for job: $job_name, build: $build_number" >&2
    return 1
  fi

  # Check if the build information contains a valid timestamp
  local timestamp
  timestamp=$(echo "$build_info" | jq -r '.timestamp')

  if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    error_message "[${FUNCNAME[0]}] Error: Invalid timestamp for job: $job_name, build: $build_number" >&2
    return 1
  fi

  echo "$timestamp"
}

function get_build_console_text() {
  local job_name=$1
  local build_number=$2
  local api_endpoint="/job/$job_name/$build_number/consoleText"
  local console_text
  console_text=$(make_jenkins_api_request "$api_endpoint")
  echo "$console_text"
}

function get_agent_from_console() {
  local job_name=$1
  local build_number=$2
  local console_text
  console_text=$(get_build_console_text "$job_name" "$build_number")

  # Now console_text contains the console output, and we can pass it to extract_agent_info_from_console
  local agent_info
  agent_info=$(extract_agent_info_from_console <<<"$console_text")
  echo "$agent_info"
}

function extract_agent_info_from_console() {
  local agent_info
  agent_info=$(grep -o -P 'Running on \K\S+')

  # Check if there are multiple agent names in the output
  if [ $(echo "$agent_info" | wc -l) -gt 1 ]; then
    while read -r line; do
      [ -n "$line" ] && echo "$line"
    done <<<"$agent_info"
  elif [ -n "$agent_info" ]; then
    echo "$agent_info"
  fi
}

# Function to get the usage count of an agent
function get_agent_usage_count() {
  local agent_name=$1
  local usage_count=${agent_usage_count["$agent_name"]}
  echo "$usage_count"
}

# Function to get the last used timestamp of an agent
function get_agent_last_used_timestamp() {
  local agent_name=$1
  local last_used_timestamp=""

  # Loop through all the multibranch pipeline jobs
  for job in "${multibranch_jobs[@]}"; do
    valid_multibranch_jobs=()
    while read -r sub_job_url; do
      # Extract the sub-job name from the URL
      sub_job=$(basename "$sub_job_url")
      valid_multibranch_jobs+=("$sub_job")
      agent=$(get_agent_for_sub_job "$job" "$sub_job")
      if [ "$agent" == "$agent_name" ]; then
        # Get the last build timestamp for the sub-job
        last_build_number=$(get_last_build_number_for_job "$job/job/$sub_job")
        timestamp=$(get_build_timestamp "$job/job/$sub_job" "$last_build_number")
        if [ -n "$timestamp" ] && [ "$timestamp" -gt "$last_used_timestamp" ]; then
          last_used_timestamp="$timestamp"
        fi
      fi
    done < <(get_valid_multibranch_jobs "$job")
  done

  echo "$last_used_timestamp"
}

function get_job_info() {
  local job_name=$1
  local api_endpoint="/job/$job_name/config.xml"
  local job_info
  job_info=$(make_jenkins_api_request "$api_endpoint")
  echo "$job_info"
}

function get_valid_multibranch_jobs() {
    local job_name=$1
    local api_endpoint="/job/$job_name/api/json"
    local job_info
    job_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$job_info" ]; then
        error_message "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
        return
    fi

    # Get valid multibranch jobs for the given job_name
    local multibranch_jobs
    multibranch_jobs=$(echo "$job_info" | jq -r '.jobs[] | select(.color != "disabled") | .url')
    echo "$multibranch_jobs"
}
