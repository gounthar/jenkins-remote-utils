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

TEMP_DEBUG_FILE=$(mktemp)

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
get_all_jobs >"$TEMP_JOB_FILE"
cat "$TEMP_JOB_FILE"

# Filter pipeline jobs
pipeline_jobs=()
while read -r job; do
  if is_pipeline_job "$job"; then
    pipeline_jobs+=("$job")
  fi
done <"$TEMP_JOB_FILE"

# Filter freestyle jobs
freestyle_jobs=()
while read -r job; do
  if is_freestyle_job "$job"; then
    freestyle_jobs+=("$job")
  fi
done <"$TEMP_JOB_FILE"

# Filter multibranch pipeline jobs
multibranch_jobs=()
while read -r job; do
  if is_multibranch_job "$job"; then
    multibranch_jobs+=("$job")
  fi
done <"$TEMP_JOB_FILE"

# Associative array to store the job builds
declare -A job_builds

# Print the title for the first multibranch job
print_subtitle "Finding sub jobs in multibranch pipelines"

# Gather sub-jobs for each multibranch pipeline job
while read -r job_url; do
  job_type=$(get_job_type "$job_url")
  if [[ "$job_type" == "multibranch" ]]; then
    process_job "$job_url" "$job_type"
  fi
done <"$TEMP_JOB_FILE"

# Add freestyle and pipeline jobs to the job tree
while read -r job_url; do
  job_type=$(get_job_type "$job_url")
  if [[ "$job_type" == "freestyle" || "$job_type" == "pipeline" ]]; then
    process_job "$job_url" "$job_type"
  fi
done <"$TEMP_JOB_FILE"

print_subtitle "Displaying raw associative arrays"
# Print the associative arrays
display_associative_array "job_builds" job_builds
display_associative_array "job_tree" job_tree

display_agents_summary

info_message "TEMP_DEBUG_FILE: $TEMP_DEBUG_FILE"

# Clean up temporary files
rm "$TEMP_JOB_FILE"
