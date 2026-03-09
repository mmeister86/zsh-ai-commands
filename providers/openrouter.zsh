#!/bin/zsh
# ==============================================================================
# Provider: OpenRouter
# ==============================================================================
# Implements the OpenRouter API provider for zsh-ai-commands.
# OpenRouter provides unified access to multiple LLM providers through a single API.
# API Docs: https://openrouter.ai/docs/quickstart
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------

typeset -g PROVIDER_NAME="openrouter"
typeset -g PROVIDER_DISPLAY_NAME="OpenRouter"
typeset -g PROVIDER_API_BASE="https://openrouter.ai/api/v1"
typeset -ga PROVIDER_MODELS=(
    # Top-Tier (paid)
    "anthropic/claude-4.6-sonnet-20260217"
    "google/gemini-2.5-flash"
    "deepseek/deepseek-v3.2-20251201"
    # Free options
    "stepfun/step-3.5-flash:free"
    "arcee-ai/trinity-large-preview:free"
    # Alternatives
    "openai/gpt-4.1-nano"
    "meta-llama/llama-3.3-70b-instruct"
    "x-ai/grok-4.1-fast"
    "minimax/minimax-m2.5-20260211"
)
typeset -g PROVIDER_DEFAULT_MODEL="google/gemini-2.5-flash"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_OPENROUTER_API_KEY"
typeset -g PROVIDER_KEY_FILE="openrouter_key"

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
    if [[ -z "$api_key" ]]; then
        # Use dynamic variable lookup for the env var name
        api_key="${(P)PROVIDER_KEY_ENV_VAR:-}"
    fi

    if [[ -z "$api_key" ]]; then
        return 1
    fi

    REPLY="$api_key"
    return 0
}

# Make API request to OpenRouter chat/completions endpoint (OpenAI-compatible)
# Arguments: $1 = request body (JSON string)
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
        echo "zsh-ai-commands::Error::No API key found for OpenRouter provider."
        echo "Please either:"
        echo "  1. Create $ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE with your API key"
        echo "  2. Set $PROVIDER_KEY_ENV_VAR environment variable"
        return 1
    }
    local api_key="$REPLY"

    while (( attempt <= max_retries )); do
        response=$(curl -s -S \
            --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${api_key}" \
            -H "HTTP-Referer: https://github.com/user/zsh-ai-commands" \
            -H "X-OpenRouter-Title: zsh-ai-commands" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/chat/completions" 2>&1)
        local curl_exit=$?

        _zsh_ai_provider_split_http_response "$response"
        http_code="$_ZSH_AI_PROVIDER_HTTP_CODE"
        response="$REPLY"

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid API key (HTTP 401)"
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
                _zsh_ai_provider_error_message "$response"
                local provider_error="$REPLY"
                if [[ -n "$provider_error" ]]; then
                    echo "zsh-ai-commands::Error::API request failed with HTTP $http_code: $provider_error"
                else
                    echo "zsh-ai-commands::Error::API request failed with HTTP $http_code"
                fi
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
            echo "zsh-ai-commands::Error::Failed to connect to API server"
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

# Parse OpenRouter API response to extract command content (OpenAI-compatible format)
# Arguments: $1 = raw API response body
# Returns: Extracted commands via REPLY variable (newline-separated)
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    _zsh_ai_provider_parse_openai_text "$response"
    parsed="$REPLY"

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        # Check for API error message
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::API error: $error_msg"
            return 1
        fi

        if [[ -z "$parsed" || "$parsed" == "null" ]]; then
            echo "zsh-ai-commands::Error::Failed to parse API response"
            return 1
        fi
    fi

    # Deduplicate and return
    REPLY=$(echo "$parsed" | uniq)
    return 0
}
