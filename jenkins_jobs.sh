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
