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

# Function to get the job type based on its URL
get_job_type() {
  local job_url="$1"
  if is_multibranch_job "$job_url"; then
    echo "multibranch"
  elif is_freestyle_job "$job_url"; then
    echo "freestyle"
  elif is_pipeline_job "$job_url"; then
    echo "pipeline"
  else
    echo "unknown"
  fi
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

# Function to process a job, its sub-jobs (if any), and store the last 10 builds
process_job() {
  local job_url="$1"
  local job_type="$2"
  local job_short_path=${job_url//$JENKINS_URL/}
  standard_message "[${FUNCNAME[0]}] Processing $job_type job: $job_url with path $job_short_path"

  if [[ "$job_type" == "multibranch" ]]; then
    standard_message "[${FUNCNAME[0]}] $job_url is a multibranch pipeline job"
    valid_multibranch_jobs=()
    while read -r sub_job_url; do
      # Extract the sub-job name from the URL
      sub_job=$(basename "$sub_job_url")
      standard_message "[${FUNCNAME[0]}] $sub_job is a sub job of $job_url"
      valid_multibranch_jobs+=("$sub_job")
      # Store the last 10 builds for the sub-job
      job_builds["$job_url/$sub_job"]=$(get_last_10_build_numbers_for_job "$job_url/job/$sub_job")
      # Process the agents for the sub-job builds
      get_agents_for_builds "$job_url/job/$sub_job" "${job_builds["$job_url/$sub_job"]}"
    done < <(get_valid_multibranch_jobs "$job_url")
    standard_message "[${FUNCNAME[0]}] Sub-jobs for $job_url: ${valid_multibranch_jobs[@]}"
    job_tree["$job_url"]=${valid_multibranch_jobs[@]} # Store sub-jobs under parent job in the tree
  else
    # Since freestyle and pipeline jobs have no sub-jobs, we directly add them to the job_tree
    job_tree["$job_url"]=""                                                       # Empty string for sub-jobs since there are none
    job_builds["$job_url"]=$(get_last_10_build_numbers_for_job "$job_short_path") # Store the last 10 builds for the job
    # Process the agents for the job builds
    get_agents_for_builds "$job_short_path" "${job_builds["$job_url"]}"
  fi
}

function get_agents_for_builds() {
  local job_name=$1
  local last_10_builds=($2) # Convert the string to an array of build numbers

  debug_message "[${FUNCNAME[0]}] Getting console output for job: $job_name, builds: ${last_10_builds[*]}"

  for build_number in "${last_10_builds[@]}"; do
    local api_endpoint="/job/$job_name/$build_number/consoleText"

    debug_message "[${FUNCNAME[0]}] Getting console output for job: $job_name, build: $build_number"

    local console_output
    console_output=$(make_jenkins_api_request "$api_endpoint")

    # Add this debug message to verify the console output contents
    debug_message "[${FUNCNAME[0]}] Console output for job: $job_name, build: $build_number"
    # debug_message "$console_output"

    if [ -n "$console_output" ]; then
      debug_message "[${FUNCNAME[0]}] Job: $job_name, Build: $build_number"
      local agent_info
      agent_info=$(extract_agent_info_from_console "$console_output")
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
  debug_message "Builds Info: $builds_info" | tail -n 10
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
  debug_message "[${FUNCNAME[0]}] Builds Info: $builds_info" | tail -n 10
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

  # debug_message "[${FUNCNAME[0]}] Build Info: $build_info"

  # Check if the build information contains a valid timestamp
  local timestamp
  timestamp=$(echo "$build_info" | jq -r '.timestamp')
  debug_message "[${FUNCNAME[0]}] Timestamp: $timestamp"
  local last_used_date
  last_used_date=$(date -d $timestamp '+%Y-%m-%d %H:%M:%S')
  debug_message "[${FUNCNAME[0]}] Timestamp: $last_used_date"
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

# Function to extract agent info from the console output
function extract_agent_info_from_console() {
  local console_output="$1"
  local agent_info
  agent_info=$(echo "$console_output" | grep -o 'Running on .* in' | sed -e 's/Running on //g' -e 's/ in//g')
  debug_message "[${FUNCNAME[0]}] Agent info: $agent_info"

  # Add this debug message to display the agent information extracted from the console
  debug_message "[${FUNCNAME[0]}] Extracted Agent info: $(echo "$agent_info" | tr '\n' ' ')"

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
