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

declare -A agent_usage  # New line to declare the associative array
declare -A agent_timestamps  # New line to declare the associative array
declare -A active_agents  # New line to declare the associative array
declare -A inactive_agents  # New line to declare the associative array

# Function to print a title with a colored background
function print_title() {
    local title_text=$1
    echo -e "\e[44m\e[97m$title_text\e[0m"  # Blue background, white text, reset formatting
}

# Function to print a colored subtitle
function print_subtitle() {
    local subtitle_text=$1
    echo -e "\e[96m$subtitle_text\e[0m"  # Cyan text, reset formatting
}

function make_jenkins_api_request() {
    local api_endpoint=$1
    curl -s -k -u $USERNAME:$API_TOKEN "${JENKINS_URL}${api_endpoint}"
}

function get_defined_agents() {
    #set -x
    local api_endpoint=/computer/api/json
    local agents_info
    agents_info=$(make_jenkins_api_request $api_endpoint)
    echo "$agents_info" | jq -r '.computer | map(select(.displayName != null)) | .[].displayName'
}

# Function to check if an agent is active or inactive
function is_agent_active() {
    local agent=$1
    local api_endpoint="/computer/$agent/api/json"
    local agent_info
    agent_info=$(make_jenkins_api_request "$api_endpoint")
    local offline
    offline=$(echo "$agent_info" | jq -r '.offline')
    [ "$offline" = "false" ]
}

function get_all_jobs() {
   set -x
    local api_endpoint="/api/json"
    local all_jobs
    all_jobs=$(make_jenkins_api_request "$api_endpoint" | jq -r '.jobs[].url' | awk -F'/' '{print $(NF-1)}')
    echo "$all_jobs"
}

function is_multibranch_job() {
    set -x
    local job_name=$1
    local api_endpoint="/job/$job_name/api/json"
    local job_info
    job_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "Error: Unable to retrieve information for job $job_name"
        return
    fi

    # Check if the job is a multibranch pipeline
    local job_class
    job_class=$(echo "$job_info" | jq -r '._class')
    [ "$job_class" = "org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" ]
}

function get_valid_multibranch_jobs() {
    local job_name=$1
    local api_endpoint="/job/$job_name/api/json"
    local job_info
    job_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_name"
        return
    fi

    # Get valid multibranch jobs for the given job_name
    local multibranch_jobs
    multibranch_jobs=$(echo "$job_info" | jq -r '.jobs[] | select(.color != "disabled") | .url')
    echo "$multibranch_jobs"
}

function get_last_10_builds_for_job() {
    local job_url=${1//$JENKINS_URL/}
    local api_endpoint="api/json"
    local job_info
    job_info=$(make_jenkins_api_request "$job_url$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_url"
        return
    fi

    # Get the last 10 build numbers for the job
    local builds_info
    builds_info=$(echo "$job_info" | jq -r '.builds | .[].number')
    echo "$builds_info"
}

function get_build_timestamp() {
    local job_name=${1//$JENKINS_URL/}
    local build_number=$2
    local api_endpoint="${job_name}/${build_number}/api/json?pretty=true"
    local build_info
    build_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$build_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve build information for job: $job_name, build: $build_number"
        return
    fi

    # Get the timestamp of the build
    local timestamp
    timestamp=$(echo "$build_info" | jq -r '.timestamp')
    echo "$timestamp"
}

function get_build_console_text() {
    local job_name=${1//$JENKINS_URL/}
    local build_number=$2

    local api_endpoint="${job_name}/${build_number}/consoleText"
    local console_output
    console_output=$(make_jenkins_api_request "$api_endpoint")

    echo "$console_output"
}

function extract_agent_info_from_console() {
    local console_file=$1
    local agent_info
    agent_info=$(grep -o -P 'Running on \K\S+' "$console_file")

    # Check if there are multiple agent names in the output
    if [ $(echo "$agent_info" | wc -l) -gt 1 ]; then
        while read -r line; do
            [ -n "$line" ] && agent_usage["$line"]=$((agent_usage["$line"] + 1))

            # Get the build timestamp for the current job and update the agent's timestamp if it's greater
            local build_timestamp
            build_timestamp=$(get_build_timestamp "$valid_job_url" "$build_number")
            local current_timestamp="${agent_timestamps[$line]}"
            if [ -z "$current_timestamp" ] || [ "$build_timestamp" -gt "$current_timestamp" ]; then
                agent_timestamps["$line"]="$build_timestamp"
            fi

            # Determine if the agent is active or inactive
            if is_agent_active "$line"; then
                active_agents["$line"]="${agent_timestamps[$line]}"
            else
                inactive_agents["$line"]="${agent_timestamps[$line]}"
            fi
        done <<< "$agent_info"
    elif [ -n "$agent_info" ]; then
        agent_usage["$agent_info"]=$((agent_usage["$agent_info"] + 1))

        # Get the build timestamp for the current job and update the agent's timestamp if it's greater
        local build_timestamp
        build_timestamp=$(get_build_timestamp "$valid_job_url" "$build_number")
        local current_timestamp="${agent_timestamps[$agent_info]}"
        if [ -z "$current_timestamp" ] || [ "$build_timestamp" -gt "$current_timestamp" ]; then
            agent_timestamps["$agent_info"]="$build_timestamp"
        fi

        # Determine if the agent is active or inactive
        if is_agent_active "$agent_info"; then
            active_agents["$agent_info"]="${agent_timestamps[$agent_info]}"
        else
            inactive_agents["$agent_info"]="${agent_timestamps[$agent_info]}"
        fi
    fi
}

# Function to convert timestamp to human-readable date
function convert_timestamp_to_date() {
    local timestamp=$1
    date -d "@$((timestamp / 1000))" +"%Y-%m-%d %H:%M:%S"
}

# Step 1: Gather a list of all defined agents
agents=$(get_defined_agents)
print_title "Step 1: Gather a list of all defined agents"
for agent in $agents; do
    echo "Agent: $agent"
done

# Step 2: Get information about each job
all_jobs=$(get_all_jobs)

# Step 3: Determine if each job is a multibranch pipeline and get valid multibranch jobs
for job_name in $all_jobs; do
    if is_multibranch_job "$job_name"; then
        valid_multibranch_jobs=$(get_valid_multibranch_jobs "$job_name")
        for valid_job_url in $valid_multibranch_jobs; do
            last_10_builds=$(get_last_10_builds_for_job "$valid_job_url")
            for build_number in $last_10_builds; do
                console_text=$(get_build_console_text "$valid_job_url" "$build_number")
                echo "$console_text" > "console_output.txt"  # Save console output to a file
                extract_agent_info_from_console "console_output.txt"
            done
        done
    fi
done

# Step 4: Display the agents and their usage count
print_title "Step 4: Display the agents and their usage count"
for agent in "${!agent_usage[@]}"; do
    echo "Agent: $agent, Usage: ${agent_usage[$agent]}"
done

# Step 5: Sort the agents based on their usage (descending order)
print_title "Step 5: Sort the agents based on their usage (descending order)"
sorted_agents=$(for agent in "${!agent_usage[@]}"; do
    echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: ${agent_timestamps[$agent]}"
done | sort -k8 -nr)

# Step 6: Display the sorted agents and their usage count
echo "Sorted Agents and their usage count:"
echo "$sorted_agents"

# Display active agents
print_subtitle "Active Agents:"
for agent in "${!active_agents[@]}"; do
    echo "Agent: $agent, Latest Build Timestamp: ${active_agents[$agent]} ($(convert_timestamp_to_date ${active_agents[$agent]}))"
done

# Display inactive agents
print_subtitle "Inactive Agents:"
for agent in "${!inactive_agents[@]}"; do
    echo "Agent: $agent, Latest Build Timestamp: ${inactive_agents[$agent]} ($(convert_timestamp_to_date ${inactive_agents[$agent]}))"
done







