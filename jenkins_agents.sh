#!/bin/bash

# Source the utility functions from jenkins_utils.sh
source ./jenkins_utils.sh

function get_defined_agents() {
    local api_endpoint="/computer/api/json"
    local defined_agents
    defined_agents=$(make_jenkins_api_request "$api_endpoint" | jq -r '.computer | .[].displayName')
    echo "$defined_agents"
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

function extract_agent_info_from_build_info() {
    local build_info=$1

    # Extract agent information from the build information
    local agent_info
    agent_info=$(echo "$build_info" | jq -r '.builtOn')

    echo "$agent_info"
}

function get_agents_for_builds() {
    local job_name=$1
    local last_10_builds=($(get_last_10_builds_for_job "$job_name"))
    local jenkins_url="http://localhost:8080"

    for build_number in "${last_10_builds[@]}"; do
        local api_endpoint="/job/$job_name/$build_number/consoleText"
        local console_output=$(make_jenkins_api_request "$api_endpoint")
        if [ -n "$console_output" ]; then
            echo "Job: $job_name, Build: $build_number"
            local agent_info=$(extract_agent_info_from_console <(echo "$console_output"))
            echo "Agent: $agent_info"
            echo "--------------"
        else
            echo "Error: Unable to retrieve console output for job: $job_name, build: $build_number" >&2
        fi
    done
}