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

# Associative arrays to store agent usage information
declare -A agent_usage_count
declare -A agent_last_used_timestamp
declare -A agent_last_used

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

# Source the agent-related functions from jenkins_agents.sh
source ./jenkins_agents.sh

# Source the job-related functions from jenkins_jobs.sh
source ./jenkins_jobs.sh

# Temporary file to store data
TEMP_AGENT_FILE=$(mktemp)
TEMP_JOB_FILE=$(mktemp)
TEMP_MULTIBRANCH_JOB_FILE=$(mktemp)

# Function to log debug messages to a temporary file
function debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: $@" >> "$TEMP_AGENT_FILE"
    fi
}

# Step 1: Gather a list of all defined agents
debug "Step 1: Gather a list of all defined agents"
get_defined_agents > "$TEMP_AGENT_FILE"

# Display the list of found agents
echo "Agents:"
while read -r agent; do
    echo "Agent: $agent"
done < "$TEMP_AGENT_FILE"

# Step 2: Get information about each job
debug "Step 2: Get information about each job"
get_all_jobs > "$TEMP_JOB_FILE"

# Display the list of declared jobs
echo -e "\nDeclared Jobs:"
while read -r job; do
    echo "Job: $job"
done < "$TEMP_JOB_FILE"

# Step 3: Initialize agent usage count to zero for all agents
while read -r agent; do
    agent_usage_count["$agent"]=0
    agent_last_used["$agent"]="N/A"  # Initialize last used timestamp to "N/A"
done < "$TEMP_AGENT_FILE"

# Step 4: Filter multibranch pipeline jobs
debug "Step 4: Filter multibranch pipeline jobs"
multibranch_jobs=()
while read -r job; do
    if is_multibranch_job "$job"; then
        multibranch_jobs+=("$job")
    fi
done < "$TEMP_JOB_FILE"

# Display the list of multibranch pipeline jobs
echo -e "\nMulti-Branch Pipeline Jobs:"
for job in "${multibranch_jobs[@]}"; do
    echo "Job: $job"
done

# Step 5: Get sub-jobs for each multibranch pipeline job
echo -e "\nSub-Jobs for Multi-Branch Pipeline Jobs:"
for job in "${multibranch_jobs[@]}"; do
    echo "Job: $job"
    valid_multibranch_jobs=()
    while read -r sub_job_url; do
        # Extract the sub-job name from the URL
        sub_job=$(basename "$sub_job_url")
        valid_multibranch_jobs+=("$sub_job")

        # Store agent information for each sub-job in the associative array
        agent_info["$job/$sub_job"]=$(get_agent_from_console "$job/job/$sub_job" "$(get_last_build_number_for_job "$job/job/$sub_job")")
    done < <(get_valid_multibranch_jobs "$job")

    # Display the sub-jobs for the current multibranch pipeline job
    for sub_job in "${valid_multibranch_jobs[@]}"; do
        echo "Sub-Job: $sub_job"
        last_10_builds=$(get_last_10_builds_for_job "$job/job/$sub_job")
        echo "Last 10 Builds: $last_10_builds"

        # Update agent usage information for each sub-job
        agent="${agent_info["$job/$sub_job"]}"
        if [ -n "$agent" ]; then
            ((agent_usage_count["$agent"]++))
            agent_last_used["$agent"]=$(date +"%Y-%m-%d %H:%M:%S")
        fi
    done
    echo
done

# Step 6: Gather agent usage count and last used timestamp
echo -e "\nAgent Usage Count and Last Used Timestamp:"

# Display the agent usage count and last used timestamp
for agent_name in "${!agent_usage_count[@]}"; do
    echo "Agent: $agent_name"
    echo "Usage Count: ${agent_usage_count["$agent_name"]}"
    last_used_timestamp="${agent_last_used["$agent_name"]}"
    if [ "$last_used_timestamp" != "N/A" ]; then
        last_used_date=$(date -d "@$last_used_timestamp" +"%Y-%m-%d %H:%M:%S")
        echo "Last Used Timestamp: $last_used_timestamp (Date: $last_used_date)"
    else
        echo "Last Used Timestamp: N/A"
    fi
    echo
done

# Display agent usage information
echo -e "\nAgent Usage Information:"
for agent in "${!agent_usage_count[@]}"; do
    echo "Agent: $agent"
    echo "Usage Count: ${agent_usage_count[$agent]}"
    echo "Last Used: ${agent_last_used[$agent]}"
    echo
done

# Clean up temporary files
rm "$TEMP_AGENT_FILE" "$TEMP_JOB_FILE" "$TEMP_MULTIBRANCH_JOB_FILE"
