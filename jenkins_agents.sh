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
