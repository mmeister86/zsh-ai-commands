#!/bin/zsh
# ==============================================================================
# Provider: Anthropic
# ==============================================================================
# Implements the Anthropic API provider for zsh-ai-commands.
# Supports Claude 4 model family.
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------

typeset -g PROVIDER_NAME="anthropic"
typeset -g PROVIDER_DISPLAY_NAME="Anthropic Claude"
typeset -g PROVIDER_API_BASE="https://api.anthropic.com/v1"
typeset -ga PROVIDER_MODELS=(
    "claude-opus-4-6-20250219"
    "claude-sonnet-4-6-20250219"
    "claude-sonnet-4-5-20250929"
    "claude-haiku-4-5-20251015"
)
typeset -g PROVIDER_DEFAULT_MODEL="claude-sonnet-4-6-20250219"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_ANTHROPIC_API_KEY"
typeset -g PROVIDER_KEY_FILE="anthropic_key"

# ------------------------------------------------------------------------------
# REQUIRED FUNCTIONS
# ------------------------------------------------------------------------------

# Get API key from file or environment variable
# Returns: API key via REPLY variable
# Returns: 0 on success, 1 if no key available
_zsh_ai_provider_get_api_key() {
    local api_key=""
    local key_file="$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE"

    # Try to load from key file first
    if [[ -f "$key_file" ]]; then
        api_key=$(head -n1 "$key_file" 2>/dev/null | tr -d '\n\r')
    fi

    # Fall back to environment variable
    if [[ -z "$api_key" && -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        # Use dynamic variable lookup for the env var name
        eval "api_key=\${$PROVIDER_KEY_ENV_VAR:-}"
    fi

    if [[ -z "$api_key" ]]; then
        return 1
    fi

    REPLY="$api_key"
    return 0
}

# Make API request to Anthropic messages endpoint
# Arguments: $1 = request body (JSON string in OpenAI format)
# Returns: Raw response via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_make_request() {
    local request_body="$1"
    local max_retries=2
    local timeout="${ZSH_AI_COMMANDS_TIMEOUT:-30}"
    local attempt=0
    local response=""
    local http_code=""

    # Get API key
    _zsh_ai_provider_get_api_key || {
        echo "zsh-ai-commands::Error::No API key found for Anthropic provider."
        echo "Please either:"
        echo "  1. Create $ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE with your API key"
        echo "  2. Set $PROVIDER_KEY_ENV_VAR environment variable"
        return 1
    }
    local api_key="$REPLY"

    # Get model
    local model="${ZSH_AI_COMMANDS_LLM_NAME:-$PROVIDER_DEFAULT_MODEL}"

    # Transform request from OpenAI format to Anthropic format
    local max_tokens=1024

    # Extract system prompt from messages
    local system_prompt=$(echo "$request_body" | jq -r '.messages[] | select(.role == "system") | .content' 2>/dev/null | head -1)

    # Extract non-system messages
    local user_messages=$(echo "$request_body" | jq '.messages | map(select(.role != "system"))' 2>/dev/null)

    # Build Anthropic-format request
    local anthropic_request=$(jq -n \
        --arg model "$model" \
        --argjson max_tokens $max_tokens \
        --argjson messages "$user_messages" \
        --arg system "$system_prompt" \
        '{model: $model, max_tokens: $max_tokens, messages: $messages, system: $system}' 2>/dev/null)

    while (( attempt <= max_retries )); do
        response=$(curl -s -S \
            --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${api_key}" \
            -H "anthropic-version: 2023-06-01" \
            -d "$anthropic_request" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/messages" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid Anthropic API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                local retry_after=$((2 ** attempt))
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying in ${retry_after} seconds..."
                sleep "$retry_after"
                (( attempt++ ))
                continue
            elif [[ "$http_code" == "500" || "$http_code" == "502" || "$http_code" == "503" || "$http_code" == "504" ]]; then
                local retry_after=$((2 ** attempt))
                echo "zsh-ai-commands::Error::Server error (HTTP $http_code). Retrying in ${retry_after} seconds..."
                sleep "$retry_after"
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::Anthropic API request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
                echo "Retrying..."
                sleep 1
                continue
            fi
            return 1
        elif (( curl_exit == 6 )); then
            echo "zsh-ai-commands::Error::Could not resolve host. Check your network connection."
            return 1
        elif (( curl_exit == 7 )); then
            echo "zsh-ai-commands::Error::Failed to connect to Anthropic API server"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
                echo "Retrying..."
                sleep 1
                continue
            fi
            return 1
        else
            echo "zsh-ai-commands::Error::curl failed with exit code $curl_exit"
            return 1
        fi
    done

    echo "zsh-ai-commands::Error::Max retries ($max_retries) exceeded"
    return 1
}

# Parse Anthropic API response to extract command content
# Arguments: $1 = raw API response body
# Returns: Extracted commands via REPLY variable (newline-separated)
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    # Extract content from Anthropic response format
    # Anthropic returns: { "content": [{ "type": "text", "text": "..." }] }
    parsed=$(echo "$response" | jq -r '.content[0].text' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        # Check for API error message
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::Anthropic API error: $error_msg"
            return 1
        fi

        echo "zsh-ai-commands::Error::Failed to parse Anthropic API response"
        return 1
    fi

    # Deduplicate and return
    REPLY=$(echo "$parsed" | uniq)
    return 0
}
