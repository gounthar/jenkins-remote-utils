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

# Redirect debug output to temporary files
function debug() {
    echo "DEBUG: $@" >> "$TEMP_AGENT_FILE"
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
    done < <(get_valid_multibranch_jobs "$job")

    # Display the sub-jobs for the current multibranch pipeline job
    for sub_job in "${valid_multibranch_jobs[@]}"; do
        echo "Sub-Job: $sub_job"
    done
    echo
done

# Clean up temporary files
rm "$TEMP_AGENT_FILE" "$TEMP_JOB_FILE" "$TEMP_MULTIBRANCH_JOB_FILE"
