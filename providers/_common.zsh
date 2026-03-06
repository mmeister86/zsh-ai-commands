#!/bin/zsh

# Shared provider helpers

typeset -g _ZSH_AI_PROVIDER_HTTP_CODE=""

_zsh_ai_provider_split_http_response() {
    local raw_response="$1"
    _ZSH_AI_PROVIDER_HTTP_CODE=$(printf '%s\n' "$raw_response" | tail -n1)
    REPLY=$(printf '%s\n' "$raw_response" | sed '$d')
    return 0
}

_zsh_ai_provider_error_message() {
    local response="$1"
    local error_type=""
    local error_msg=""

    error_type=$(printf '%s' "$response" | jq -r '.error.type // empty' 2>/dev/null)
    error_msg=$(printf '%s' "$response" | jq -r '.error.message // .message // .error // empty' 2>/dev/null)

    if [[ -n "$error_type" && -n "$error_msg" ]]; then
        REPLY="${error_type}: ${error_msg}"
        return 0
    fi
    if [[ -n "$error_msg" ]]; then
        REPLY="$error_msg"
        return 0
    fi

    REPLY=""
    return 1
}

_zsh_ai_provider_dedupe_lines() {
    local content="$1"
    REPLY=$(printf '%s\n' "$content" | awk 'NF && !seen[$0]++')
    return 0
}

_zsh_ai_provider_parse_openai_text() {
    local response="$1"
    local parsed=""

    parsed=$(printf '%s' "$response" | jq -r '
        .choices[]?.message? |
        if (.content | type) == "string" then
            .content
        elif (.content | type) == "array" then
            [ .content[]? |
              if type == "string" then .
              elif type == "object" then (.text // .content // "")
              else ""
              end
            ] | join("")
        elif (.refusal | type) == "string" then
            .refusal
        else
            ""
        end
    ' 2>/dev/null)

    if [[ -z "$parsed" ]]; then
        REPLY=""
        return 1
    fi

    _zsh_ai_provider_dedupe_lines "$parsed"
    return 0
}

_zsh_ai_provider_parse_anthropic_text() {
    local response="$1"
    local parsed=""

    parsed=$(printf '%s' "$response" | jq -r '.content[]? | select(.type == "text") | .text' 2>/dev/null)

    if [[ -z "$parsed" ]]; then
        REPLY=""
        return 1
    fi

    _zsh_ai_provider_dedupe_lines "$parsed"
    return 0
}

_zsh_ai_provider_parse_gemini_text() {
    local response="$1"
    local parsed=""

    parsed=$(printf '%s' "$response" | jq -r '.candidates[]?.content.parts[]?.text // empty' 2>/dev/null)

    if [[ -z "$parsed" ]]; then
        REPLY=""
        return 1
    fi

    _zsh_ai_provider_dedupe_lines "$parsed"
    return 0
}
