#!/bin/zsh
# ==============================================================================
# Provider: Google Gemini
# ==============================================================================
# Implements the Google Gemini API provider for zsh-ai-commands.
# Supports Gemini 2.5 stable models and Gemini 3 preview aliases.
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------

typeset -g PROVIDER_NAME="gemini"
typeset -g PROVIDER_DISPLAY_NAME="Google Gemini"
typeset -g PROVIDER_API_BASE="https://generativelanguage.googleapis.com/v1beta"
typeset -ga PROVIDER_MODELS=("gemini-2.5-flash" "gemini-2.5-pro" "gemini-3.0-flash" "gemini-3.0-pro" "gemini-flash-latest" "gemini-pro-latest")
typeset -g PROVIDER_DEFAULT_MODEL="gemini-flash-latest"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_GEMINI_API_KEY"
typeset -g PROVIDER_KEY_FILE="gemini_key"

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

# Resolve user-facing model aliases to Gemini API model IDs.
# Arguments: $1 = user-facing model name
# Returns: API model name via REPLY variable
_zsh_ai_provider_resolve_model() {
    local model="$1"

    case "$model" in
        gemini-3.0-flash)
            REPLY="gemini-3-flash-preview"
            ;;
        gemini-3.0-pro)
            REPLY="gemini-3-pro-preview"
            ;;
        *)
            REPLY="$model"
            ;;
    esac

    return 0
}

# Make API request to Gemini generateContent endpoint
# Arguments: $1 = request body (JSON string from core)
# Returns: Raw response via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model="${ZSH_AI_COMMANDS_LLM_NAME:-$PROVIDER_DEFAULT_MODEL}"
    local n="${ZSH_AI_COMMANDS_N_GENERATIONS:-1}"
    local max_retries=2
    local timeout="${ZSH_AI_COMMANDS_TIMEOUT:-30}"
    local attempt=0
    local response=""
    local http_code=""

    # Get API key
    _zsh_ai_provider_get_api_key || {
        echo "zsh-ai-commands::Error::No API key found for Gemini provider."
        echo "Please either:"
        echo "  1. Create $ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE with your API key"
        echo "  2. Set $PROVIDER_KEY_ENV_VAR environment variable"
        return 1
    }
    local api_key="$REPLY"

    _zsh_ai_provider_resolve_model "$model"
    local api_model="$REPLY"

    # Transform OpenAI-style request body to Gemini format
    # Extract the user message from the OpenAI-style messages array
    local user_prompt=$(echo "$request_body" | jq -r '.messages[] | select(.role == "user") | .content' 2>/dev/null)

    if [[ -z "$user_prompt" || "$user_prompt" == "null" ]]; then
        echo "zsh-ai-commands::Error::Failed to extract user prompt from request"
        return 1
    fi

    # Build Gemini-format request body
    # Gemini uses "contents" instead of "messages"
    local gemini_request=$(jq -n \
        --arg prompt "$user_prompt" \
        --argjson n "$n" \
        '{
            contents: [{
                parts: [{
                    text: $prompt
                }]
            }],
            generationConfig: {
                candidateCount: $n
            }
        }')

    while (( attempt <= max_retries )); do
        # Gemini uses query parameter for API key, not Authorization header
        response=$(curl -s -S \
            --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -d "$gemini_request" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/models/${api_model}:generateContent?key=${api_key}" 2>&1)
        local curl_exit=$?

        _zsh_ai_provider_split_http_response "$response"
        http_code="$_ZSH_AI_PROVIDER_HTTP_CODE"
        response="$REPLY"

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "400" ]]; then
                local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
                echo "zsh-ai-commands::Error::Bad request (HTTP 400): ${error_msg:-Unknown error}"
                return 1
            elif [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
                echo "zsh-ai-commands::Error::Invalid API key (HTTP $http_code)"
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

# Parse Gemini API response to extract command content
# Arguments: $1 = raw API response body
# Returns: Extracted commands via REPLY variable (newline-separated)
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    _zsh_ai_provider_parse_gemini_text "$response"
    parsed="$REPLY"

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        # Check for API error message
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::API error: $error_msg"
            return 1
        fi

        # Check for prompt feedback (safety blocked)
        local block_reason=$(echo "$response" | jq -r '.promptFeedback.blockReason // empty' 2>/dev/null)
        if [[ -n "$block_reason" ]]; then
            echo "zsh-ai-commands::Error::Content blocked: $block_reason"
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
