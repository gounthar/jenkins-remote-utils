#!/bin/bash

# Before running this script, make sure to set the following environment variables:
# JENKINS_URL: The URL of your Jenkins server (e.g., http://localhost:8080)
# USERNAME: Your Jenkins username (e.g., admin)
# API_TOKEN: Your Jenkins API token (generate one from Jenkins user settings)

# Check if the required environment variables are set
if [[ -z "$JENKINS_URL" || -z "$USERNAME" || -z "$API_TOKEN" ]]; then
    echo "Error: Please set the required environment variables before running this script." >&2
    echo "Required environment variables: JENKINS_URL, USERNAME, API_TOKEN" >&2
    exit 1
fi

declare -A agent_usage
declare -A agent_timestamps
declare -A active_agents
declare -A inactive_agents

# Source the agent-related functions from jenkins_agents.sh
source ./jenkins_agents.sh

# Source the job-related functions from jenkins_jobs.sh
source ./jenkins_jobs.sh

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

# Temporary file to store data
TEMP_FILE=$(mktemp)
TEMP_AGENT_FILE=$(mktemp)
TEMP_JOB_FILE=$(mktemp)

# Redirect debug output to temporary files
function debug() {
    echo "DEBUG: $@" >> "$TEMP_AGENT_FILE"
}
# Redirect debug output to temporary files
function debug_agent() {
    echo "DEBUG: $@" >> "$TEMP_AGENT_FILE"
}

function debug_job() {
    echo "DEBUG: $@" >> "$TEMP_JOB_FILE"
}

debug_agent "Step 1: Gather a list of all defined agents"
get_defined_agents > "$TEMP_FILE"
while read -r agent; do
    debug_agent "Agent: $agent"
done < "$TEMP_FILE"

debug_job "Step 2: Get information about each job"
get_all_jobs > "$TEMP_FILE"
while read -r job; do
    debug_job "Job: $job"
done < "$TEMP_FILE"

# Step 3: Get the latest build timestamp for each agent
get_defined_agents > "$TEMP_FILE"
while read -r agent; do
    debug_agent "Getting build number for agent: $agent"
    agent_info=$(extract_agent_info_from_build_info "$agent")
    debug_agent "Raw response from Jenkins API for agent $agent:"
    debug_agent "$agent_info"

    last_build_number=$(get_last_build_number_for_job "$agent_info")
    if [ -n "$last_build_number" ]; then
        debug_agent "Last build number for agent $agent: $last_build_number"
        # Use a different function to get the build timestamp
        build_timestamp=$(get_build_timestamp "$agent_info" "$last_build_number")
        if [ -n "$build_timestamp" ]; then
            debug_agent "Build timestamp for agent $agent and build number $last_build_number: $build_timestamp"
            agent_timestamps["$agent"]="$build_timestamp"
        fi
    fi
done < "$TEMP_FILE"

# Step 4: Display the agents and their usage count
function display_agents_usage() {
    echo "Step 4: Display the agents and their usage count"
    while IFS= read -r agent; do
        echo "Agent: $agent, Usage: ${agent_usage["$agent"]}"
    done < "$TEMP_AGENT_FILE"
}

# Redirect debug output to temporary files
function debug() {
    echo "DEBUG: $@" >> "$TEMP_AGENT_FILE"
}

# Step 5: Sort the agents based on their usage (descending order)
debug "Step 5: Sort the agents based on their usage (descending order)"
{
    for agent in "${!agent_usage[@]}"; do
        # Check if the timestamp is a valid number before including it in the output
        if [[ "${agent_timestamps[$agent]}" =~ ^[0-9]+$ ]]; then
            echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: ${agent_timestamps[$agent]}"
        else
            echo "Agent: $agent, Usage: ${agent_usage[$agent]}, Latest Build Timestamp: Unknown (Invalid Timestamp)"
        fi
    done
} | sort -k8 -nr > "$TEMP_FILE"

# Step 6: Display the sorted agents and their usage count
debug "Step 6: Display the sorted agents and their usage count"
echo "Sorted Agents and their usage count:"
cat "$TEMP_FILE"

# Display active agents
debug "Active Agents:"
for agent in "${!active_agents[@]}"; do
    echo "Agent: $agent, Latest Build Timestamp: ${active_agents[$agent]} ($(convert_timestamp_to_date ${active_agents[$agent]}))"
done

# Clean up temporary files
rm "$TEMP_FILE" "$TEMP_AGENT_FILE" "$TEMP_JOB_FILE"

