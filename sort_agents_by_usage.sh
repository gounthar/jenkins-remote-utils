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

declare -A agent_usage
declare -A agent_timestamps
declare -A active_agents
declare -A inactive_agents

function print_title() {
    local title_text=$1
    echo -e "\e[44m\e[97m$title_text\e[0m"
}

function print_subtitle() {
    local subtitle_text=$1
    echo -e "\e[96m$subtitle_text\e[0m"
}

function make_jenkins_api_request() {
    local api_endpoint=$1
    curl -s -k -u $USERNAME:$API_TOKEN "${JENKINS_URL}${api_endpoint}"
}

function get_defined_agents() {
    local api_endpoint=/computer/api/json
    local agents_info
    agents_info=$(make_jenkins_api_request $api_endpoint)
    echo "$agents_info" | jq -r '.computer | map(select(.displayName != null)) | .[].displayName'
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

function get_all_jobs() {
    local api_endpoint="/api/json"
    local all_jobs
    all_jobs=$(make_jenkins_api_request "$api_endpoint" | jq -r '.jobs | .[].name')
    echo "$all_jobs"
}

function get_last_build_number_for_job() {
    local job_name=$1
    local api_endpoint="/job/$job_name/lastBuild/api/json"
    local last_build_info
    last_build_info=$(make_jenkins_api_request "$api_endpoint")
    echo "$last_build_info" | jq -r '.number'
}

function get_build_timestamp() {
    local job_name=$1
    local build_number=$2
    local api_endpoint="/job/$job_name/$build_number/api/json?pretty=true"
    local build_info
    build_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$build_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve build information for job: $job_name, build: $build_number"
        return
    fi

    # Debug output: Display the raw response from Jenkins API
    echo "[${FUNCNAME[0]}] Raw Build Info for job: $job_name, build: $build_number"
    echo "$build_info"

    # Check if the build information contains a valid timestamp
    local timestamp
    timestamp=$(echo "$build_info" | jq -r '.timestamp')

    # Debug output: Display the extracted timestamp
    echo "[${FUNCNAME[0]}] Extracted Timestamp for job: $job_name, build: $build_number"
    echo "$timestamp"

    if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "[${FUNCNAME[0]}] Error: Invalid timestamp for job: $job_name, build: $build_number"
        return
    fi

    echo "$timestamp"
}

function extract_agent_info_from_build_info() {
    local build_info=$1

    # Extract agent information from the build information
    local agent_info
    agent_info=$(echo "$build_info" | jq -r '.builtOn')

    if [ -n "$agent_info" ]; then
        agent_usage["$agent_info"]=$((agent_usage["$agent_info"] + 1))

        # Get the build timestamp and update the agent's timestamp if it's greater
        local timestamp
        timestamp=$(echo "$build_info" | jq -r '.timestamp')
        local current_timestamp="${agent_timestamps[$agent_info]}"
        if [ -z "$current_timestamp" ] || [ "$timestamp" -gt "$current_timestamp" ]; then
            agent_timestamps["$agent_info"]="$timestamp"
        fi

        # Determine if the agent is active or inactive
        if is_agent_active "$agent_info"; then
            active_agents["$agent_info"]="${agent_timestamps[$agent_info]}"
        else
            inactive_agents["$agent_info"]="${agent_timestamps[$agent_info]}"
        fi
    else
        # If there is no agent information in the build information, consider it as an unknown agent
        local unknown_agent="UnknownAgent"
        agent_usage["$unknown_agent"]=$((agent_usage["$unknown_agent"] + 1))

        # Get the build timestamp and update the agent's timestamp if it's greater
        local timestamp
        timestamp=$(echo "$build_info" | jq -r '.timestamp')
        local current_timestamp="${agent_timestamps["$unknown_agent"]}"
        if [ -z "$current_timestamp" ] || [ "$timestamp" -gt "$current_timestamp" ]; then
            agent_timestamps["$unknown_agent"]="$timestamp"
        fi

        # Determine if the agent is active or inactive
        if is_agent_active "$unknown_agent"; then
            active_agents["$unknown_agent"]="${agent_timestamps["$unknown_agent"]}"
        else
            inactive_agents["$unknown_agent"]="${agent_timestamps["$unknown_agent"]}"
        fi
    fi
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
            build_timestamp=$(get_build_timestamp "$job_name" "$build_number")
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
        build_timestamp=$(get_build_timestamp "$job_name" "$build_number")
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

function convert_timestamp_to_date() {
    local timestamp=$1
    if [ -n "$timestamp" ]; then
        date -d "@$((timestamp / 1000))" +"%Y-%m-%d %H:%M:%S"
    else
        echo "Unknown Timestamp"
    fi
}

# Step 4: Display the agents and their usage count
function display_agents_usage() {
    echo "Step 4: Display the agents and their usage count"
    for agent in "${!agent_usage[@]}"; do
        echo "Agent: $agent, Usage: ${agent_usage[$agent]}"
    done
}

# Step 1: Gather a list of all defined agents
agents=$(get_defined_agents)
print_title "Step 1: Gather a list of all defined agents"
for agent in $agents; do
    echo "Agent: $agent"
done

# Step 2: Get information about each job
all_jobs=$(get_all_jobs)

# Step 3: Get the latest build timestamp for each agent
echo "Step 3: Get the latest build timestamp for each agent"
for agent in $agents; do
    last_build_number=$(get_last_build_number_for_job "$agent")
    if [ -n "$last_build_number" ]; then
        # Use a different function to get the build timestamp
        build_timestamp=$(get_build_timestamp "$agent" "$last_build_number")
        if [ -n "$build_timestamp" ]; then
            agent_timestamps["$agent"]="$build_timestamp"
        fi
    fi
done

# Step 4: Display the agents and their usage count
display_agents_usage

# Step 5: Sort the agents based on their usage (descending order)
print_title "Step 5: Sort the agents based on their usage (descending order)"
sorted_agents=$(for agent in "${!agent_usage[@]}"; do
    # Check if the timestamp is a valid number before including it in the output
    if [[ "${agent_timestamps[$agent]}" =~ ^[0-9]+$ ]]; then
        echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: ${agent_timestamps[$agent]}"
    else
        echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: Unknown (Invalid Timestamp)"
    fi
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
