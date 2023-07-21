#!/bin/bash

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
    local build_number
    build_number=$(echo "$last_build_info" | jq -r '.number')
    echo "$build_number"
}
function is_multibranch_job() {
    # set -x
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

function get_multibranch_pipeline_jobs() {
    local api_endpoint="/api/json"
    local all_jobs
    all_jobs=$(make_jenkins_api_request "$api_endpoint" | jq -r '.jobs | .[].name')

    # Filter only the multi-branch pipeline jobs
    local multibranch_jobs
    while read -r job; do
        if is_multibranch_job "$job"; then
            multibranch_jobs+=" $job"
        fi
    done <<< "$all_jobs"

    echo "$multibranch_jobs"
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
    job_info=$(make_jenkins_api_request "/job/$job_url/$api_endpoint")

    if [ -z "$job_info" ]; then
        echo "[${FUNCNAME[0]}] Error: Unable to retrieve information for job $job_url using /job/$job_url/$api_endpoint"
        return
    fi

    # Debug: Output the API response for the job
    echo "API Response for job $job_url:"
    echo "$job_info"

    # Get the last 10 build numbers for the job
    local builds_info
    builds_info=$(echo "$job_info" | jq -r '.builds | .[].number')
    echo "$builds_info"
}

function get_build_timestamp() {
    local job_name=$1
    local build_number=$2
    local api_endpoint="/job/$job_name/$build_number/api/json?pretty=true"
    local build_info
    build_info=$(make_jenkins_api_request "$api_endpoint")

    if [ -z "$build_info" ]; then
        echo "Error: Unable to retrieve build information for job: $job_name, build: $build_number" >&2
        return 1
    fi

    # Check if the build information contains a valid timestamp
    local timestamp
    timestamp=$(echo "$build_info" | jq -r '.timestamp')

    if ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid timestamp for job: $job_name, build: $build_number" >&2
        return 1
    fi

    echo "$timestamp"
}

function extract_agent_info_from_console() {
    local console_file=$1
    local agent_info
    agent_info=$(grep -o -P 'Running on \K\S+' "$console_file")

    # Check if there are multiple agent names in the output
    if [ $(echo "$agent_info" | wc -l) -gt 1 ]; then
        while read -r line; do
            [ -n "$line" ] && echo "$line"
        done <<< "$agent_info"
    elif [ -n "$agent_info" ]; then
        echo "$agent_info"
    fi
}

function get_job_info() {
    local job_name=$1
    local api_endpoint="/job/$job_name/config.xml"
    local job_info
    job_info=$(make_jenkins_api_request "$api_endpoint")
    echo "$job_info"
}
