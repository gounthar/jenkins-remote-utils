#!/bin/bash

# Before running this script, make sure to set the following environment variables:
# JENKINS_URL: The URL of your Jenkins server (e.g., http://localhost:8080)
# USERNAME: Your Jenkins username (e.g., admin)
# API_TOKEN: Your Jenkins API token (generate one from Jenkins user settings)

# Check if the required environment variables are set
if [[ -z "$JENKINS_URL" || -z "$USERNAME" || -z "$API_TOKEN" ]]; then
    echo "Error: Please set the required environment variables before running this script."
    echo "Required environment variables: JENKINS_URL, USERNAME, API_TOKEN"
    exit 1
fi

declare -A agent_timestamps  # New line to declare the associative array

function make_jenkins_api_request() {
    local api_endpoint=$1
    curl -s -k -u $USERNAME:$API_TOKEN "${JENKINS_URL}${api_endpoint}"
}

function get_defined_agents() {
    local api_endpoint=/computer/api/json
    local agents_info=$(make_jenkins_api_request $api_endpoint)
    echo "$agents_info" | jq -r '.computer | map(select(.displayName != null)) | .[].displayName'
}

function get_all_jobs() {
    local api_endpoint="/api/json"
    local all_jobs=$(make_jenkins_api_request "$api_endpoint" | jq -r '.jobs | .[].name')
    echo "$all_jobs"
}

function is_multibranch_job() {
    local job_name=$1
    local api_endpoint="/job/$job_name/api/json"
    local job_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "Error: Unable to retrieve information for job $job_name"
        return
    fi

    echo "Found some information about the job: $job_name"

    local job_class=$(echo "$job_info" | jq -r '._class')
    [ "$job_class" = "org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" ]

#cho "Job class: $job_class"
#cho "Job info: $job_info"
}

function get_valid_multibranch_jobs() {
  # set -x
    local job_name=$1
    local api_endpoint="/job/$job_name/api/json"
    local job_info
    job_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
        return
    fi

    local multibranch_jobs=$(echo "$job_info" | jq -r '.jobs[] | select(.color != "disabled") | .url')
    echo "$multibranch_jobs"
}

function get_last_10_builds_for_job() {
#  set -x
    local job_url=${1//$JENKINS_URL/}
    local api_endpoint="api/json"
    local job_info=$(make_jenkins_api_request "$job_url$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_url"
        return
    fi

    local builds_info=$(echo "$job_info" | jq -r '.builds | .[].number')
    echo "$builds_info"
}

function get_build_timestamp() {
    local job_name=${1//$JENKINS_URL/}
    local build_number=$2
    local api_endpoint="${job_name}/${build_number}/api/json?pretty=true"
    local build_info=$(make_jenkins_api_request "$api_endpoint")
    local timestamp=$(echo "$build_info" | jq -r '.timestamp')
    echo "$timestamp"
}

function get_build_console_text() {
    local job_name=${1//$JENKINS_URL/}
    local build_number=$2

    #echo "[${FUNCNAME[0]}] job_name: $job_name, build_number: $build_number"

    local api_endpoint="${job_name}/${build_number}/consoleText"
    local console_output
    console_output=$(make_jenkins_api_request "$api_endpoint")

    echo "$console_output"
}

function extract_agent_info_from_console() {
    local console_file=$1
    local agent_info=$(grep -o -P 'Running on \K\S+' "$console_file")

    echo "[${FUNCNAME[0]}] Found agent info: $agent_info"

    # Check if there are multiple agent names in the output
    if [ $(echo "$agent_info" | wc -l) -gt 1 ]; then
        while read -r line; do
            echo "$line"  # Debug: Display each agent name separately
            [ -n "$line" ] && agent_usage["$line"]=$((agent_usage["$line"] + 1))

            # Get the build timestamp for the current job and update the runner's timestamp if it's greater
            local build_timestamp=$(get_build_timestamp "$valid_job_url" "$build_number")
            local current_timestamp="${agent_timestamps[$line]}"
            if [ -z "$current_timestamp" ] || [ "$build_timestamp" -gt "$current_timestamp" ]; then
                agent_timestamps["$line"]="$build_timestamp"
            fi

            echo "Agent usage updated for agent: $line, usage: ${agent_usage["$line"]}, latest build timestamp: ${agent_timestamps[$line]}"
        done <<< "$agent_info"
    elif [ -n "$agent_info" ]; then
        agent_usage["$agent_info"]=$((agent_usage["$agent_info"] + 1))

        # Get the build timestamp for the current job and update the runner's timestamp if it's greater
        local build_timestamp=$(get_build_timestamp "$valid_job_url" "$build_number")
        local current_timestamp="${agent_timestamps[$agent_info]}"
        if [ -z "$current_timestamp" ] || [ "$build_timestamp" -gt "$current_timestamp" ]; then
            agent_timestamps["$agent_info"]="$build_timestamp"
        fi

        echo "Agent usage updated for agent: $agent_info, usage: ${agent_usage["$agent_info"]}, latest build timestamp: ${agent_timestamps[$agent_info]}"
    fi
}

# Function to convert timestamp to human-readable date
function convert_timestamp_to_date() {
    local timestamp=$1
    date -d "@$((timestamp / 1000))" +"%Y-%m-%d %H:%M:%S"
}

# Step 1: Gather a list of all defined agents
echo "Step 1: Gathering a list of all defined agents..."
agents=$(get_defined_agents)
echo "Defined Agents: $agents"

# Step 2: Get information about each job
echo -e "\nStep 2: Getting information about each job..."
all_jobs=$(get_all_jobs)
echo "All Jobs: $all_jobs"

# Step 3: Determine if each job is a multibranch pipeline and get valid multibranch jobs
echo -e "[${FUNCNAME[0]}] Step 3: Determining multibranch jobs and their valid branches/PRs..."
declare -A agent_usage
for job_name in $all_jobs; do
    if is_multibranch_job "$job_name"; then
        echo "[${FUNCNAME[0]}] Checking multibranch job: $job_name..."
        valid_multibranch_jobs=$(get_valid_multibranch_jobs "$job_name")
        echo "[${FUNCNAME[0]}] Valid multibranch jobs for $job_name: $valid_multibranch_jobs"
        for valid_job_url in $valid_multibranch_jobs; do
            echo "[${FUNCNAME[0]}] Fetching last 10 builds for job: $valid_job_url..."
            last_10_builds=$(get_last_10_builds_for_job "$valid_job_url")
            echo "[${FUNCNAME[0]}] Last 10 builds for job $valid_job_url: $last_10_builds"

            for build_number in $last_10_builds; do
                echo "[${FUNCNAME[0]}] Fetching console output for job: $valid_job_url, build: $build_number..."
                console_text=$(get_build_console_text "$valid_job_url" "$build_number")
                echo "[${FUNCNAME[0]}] Job: $valid_job_url, Build: $build_number, Console Output:"
                echo "$console_text" > "console_output.txt"  # Save console output to a file
                extract_agent_info_from_console "console_output.txt"
            done
        done
    fi
done

# Step 4: Display the agents and their usage count
echo "Agents and their usage count:"
for agent in "${!agent_usage[@]}"; do
    echo "Agent: $agent, Usage: ${agent_usage[$agent]}"
done

# Step 5: Sort the agents based on their usage (descending order)
echo "Step 5: Sorting the agents based on their usage..."
sorted_agents=$(for agent in "${!agent_usage[@]}"; do
    echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: ${agent_timestamps[$agent]}"
done | sort -k8 -nr)

# Step 6: Display the sorted agents and their usage count
echo "Sorted Agents and their usage count:"
echo "$sorted_agents"

# Step 7: Timestamps for each agent
echo "Step 7: Timestamps for each agent:"
for agent in "${!agent_timestamps[@]}"; do
    echo "Agent: $agent, Latest Build Timestamp: ${agent_timestamps[$agent]} ($(convert_timestamp_to_date ${agent_timestamps[$agent]}))"
done
