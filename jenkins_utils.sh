#!/bin/bash

function print_title() {
    local title_text=$1
    echo -e "\e[44m\e[97m$title_text\e[0m"
}

function print_subtitle() {
    local subtitle_text=$1
    echo -e "\n\e[1m\e[104m\e[97m$subtitle_text\e[0m"
}

function print_subsubtitle() {
    local subtitle_text=$1
    echo -e "\e[96m$subtitle_text\e[0m"
}

function make_jenkins_api_request() {
    local api_endpoint=$1
    curl -s -k -u $USERNAME:$API_TOKEN "${JENKINS_URL}${api_endpoint}"
}

function convert_timestamp_to_date() {
    local timestamp=$1
    if [ -n "$timestamp" ]; then
        date -d "@$((timestamp / 1000))" +"%Y-%m-%d %H:%M:%S"
    else
        echo "Unknown Timestamp"
    fi
}