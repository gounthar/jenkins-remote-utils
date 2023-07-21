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

# Associative array to store the job builds
declare -A job_builds
# Nested associative array to store the tree-like structure
declare -A job_tree

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

# Source the agent-related functions from jenkins_agents.sh
source ./jenkins_agents.sh

# Source the job-related functions from jenkins_jobs.sh
source ./jenkins_jobs.sh


# Print the main title
print_title "Jenkins Job Summary"

# Gather a list of all defined agents
get_defined_agents

# Print the title for the first multibranch job
print_subtitle "Finding jobs"

# Get information about each job and save it to a temporary file
TEMP_JOB_FILE=$(mktemp)
get_all_jobs > "$TEMP_JOB_FILE"

# Filter multibranch pipeline jobs
multibranch_jobs=()
while read -r job; do
    if is_multibranch_job "$job"; then
        multibranch_jobs+=("$job")
    fi
done < "$TEMP_JOB_FILE"

# Function to get the last 10 builds for a job, handling possible null values
function get_last_10_build_numbers_for_job() {
    local job_name="$1"
    builds=()
    while read -r build_number; do
        if [[ -n "$build_number" ]]; then
            builds+=("$build_number")
        fi
    done < <(get_last_build_numbers_for_job "$job_name" 10)
    echo "${builds[@]}"
}

# Associative array to store the job builds
declare -A job_builds

# Print the title for the first multibranch job
print_subtitle "Finding sub jobs in multibranch pipelines"

# Gather sub-jobs for each multibranch pipeline job
for job in "${multibranch_jobs[@]}"; do
    echo "Processing multibranch job: $job"
    valid_multibranch_jobs=()
    while read -r sub_job_url; do
        # Extract the sub-job name from the URL
        sub_job=$(basename "$sub_job_url")
        valid_multibranch_jobs+=("$sub_job")
        # Store the last 10 builds for the sub-job
        job_builds["$job/$sub_job"]=$(get_last_10_build_numbers_for_job "$job/job/$sub_job")
    done < <(get_valid_multibranch_jobs "$job")
    echo "Sub-jobs for $job: ${valid_multibranch_jobs[@]}"
    job_tree["$job"]=${valid_multibranch_jobs[@]} # Store sub-jobs under parent job in the tree
done

# Print the title for the first multibranch job
print_subtitle "Finding last 10 builds for each and every job"

# Gather the last 10 builds for each job (including base jobs and sub-jobs of multibranch jobs)
while read -r job; do
    echo "Processing job: $job"
    # Store the last 10 builds for the job
    job_builds["$job"]=$(get_last_10_build_numbers_for_job "$job")

    # Separate base job and sub-job (if any)
    IFS="/" read -r parent_job sub_job <<< "$job"
    if [[ -n "$sub_job" ]]; then
        # If sub-job, add it to the parent's sub-jobs in the tree
        if [[ -z "${job_tree["$parent_job"]}" ]]; then
            job_tree["$parent_job"]=$sub_job
        else
            job_tree["$parent_job"]+=" $sub_job"
        fi
    fi
done < "$TEMP_JOB_FILE"


# Print the title for the first multibranch job
print_subtitle "Our results"

# Display the job builds and tree-like structure
for job in "${!job_tree[@]}"; do
    echo "Job: $job"
    sub_jobs=${job_tree["$job"]}
    if [[ -n "$sub_jobs" ]]; then
        echo "Sub-jobs: $sub_jobs"
        for sub_job in $sub_jobs; do
            echo "  Sub-job: $sub_job"
            sub_job_builds=${job_builds["$job/$sub_job"]}
            if [[ -n "$sub_job_builds" ]]; then
                echo "  Last 10 Builds: ${sub_job_builds}"
            else
                echo "  Last 10 Builds: N/A"
            fi
            echo
        done
    else
        job_builds_info=${job_builds["$job"]}
        if [[ -n "$job_builds_info" ]]; then
            echo "Last 10 Builds: ${job_builds_info}"
        else
            echo "Last 10 Builds: N/A"
        fi
        echo
    fi
done

# Clean up temporary files
rm "$TEMP_JOB_FILE"
