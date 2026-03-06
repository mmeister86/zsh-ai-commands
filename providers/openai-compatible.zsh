#!/bin/zsh
# ==============================================================================
# Provider: OpenAI-Compatible (Local)
# ==============================================================================
# Implements a generic OpenAI-compatible API provider for local LLM servers.
# Compatible with LM Studio, vLLM, LocalAI, Ollama (with OpenAI API), etc.
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------

typeset -g PROVIDER_NAME="openai-compatible"
typeset -g PROVIDER_DISPLAY_NAME="OpenAI Compatible (Local)"
typeset -g PROVIDER_API_BASE="http://localhost:1234/v1"
typeset -ga PROVIDER_MODELS=("local-model")
typeset -g PROVIDER_DEFAULT_MODEL="local-model"
typeset -g PROVIDER_REQUIRES_API_KEY=false
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_COMPATIBLE_API_KEY"
typeset -g PROVIDER_KEY_FILE="compatible_key"

# ------------------------------------------------------------------------------
# HELPER: Get effective base URL
# ------------------------------------------------------------------------------
_zsh_ai_provider_get_base_url() {
    # Allow override via environment variable
    if [[ -n "${ZSH_AI_COMMANDS_COMPATIBLE_BASE:-}" ]]; then
        REPLY="$ZSH_AI_COMMANDS_COMPATIBLE_BASE"
    else
        REPLY="$PROVIDER_API_BASE"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# REQUIRED FUNCTIONS
# ------------------------------------------------------------------------------

# Get API key from file or environment variable (optional for this provider)
# Returns: API key via REPLY variable
# Returns: 0 on success, 1 if no key available (but that's okay for local servers)
_zsh_ai_provider_get_api_key() {
    local api_key=""
    local key_file="$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE"

    # Try to load from key file first
    if [[ -f "$key_file" ]]; then
        api_key=$(head -n1 "$key_file" 2>/dev/null | tr -d '\n\r')
    fi

    # Fall back to environment variable
    if [[ -z "$api_key" ]]; then
        eval "api_key=\${$PROVIDER_KEY_ENV_VAR:-}"
    fi

    # For OpenAI-compatible, no API key is acceptable (local servers often don't need auth)
    if [[ -z "$api_key" ]]; then
        REPLY=""
        return 1
    fi

    REPLY="$api_key"
    return 0
}

# Make API request to OpenAI-compatible chat/completions endpoint
# Arguments: $1 = request body (JSON string)
# Returns: Raw response via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_make_request() {
    local request_body="$1"
    local max_retries=2
    # Longer timeout for local inference (60s default)
    local timeout="${ZSH_AI_COMMANDS_TIMEOUT:-60}"
    local attempt=0
    local response=""
    local http_code=""

    # Get effective base URL
    _zsh_ai_provider_get_base_url
    local base_url="$REPLY"

    # Get API key (optional - may be empty for local servers)
    _zsh_ai_provider_get_api_key 2>/dev/null
    local api_key="$REPLY"

    # Build authorization header only if we have a key
    local auth_header=""
    if [[ -n "$api_key" ]]; then
        auth_header="-H \"Authorization: Bearer ${api_key}\""
    fi

    while (( attempt <= max_retries )); do
        if [[ -n "$api_key" ]]; then
            response=$(curl -s -S \
                --max-time "$timeout" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${api_key}" \
                -d "$request_body" \
                -w "\n%{http_code}" \
                "${base_url}/chat/completions" 2>&1)
        else
            response=$(curl -s -S \
                --max-time "$timeout" \
                -H "Content-Type: application/json" \
                -d "$request_body" \
                -w "\n%{http_code}" \
                "${base_url}/chat/completions" 2>&1)
        fi
        local curl_exit=$?

        _zsh_ai_provider_split_http_response "$response"
        http_code="$_ZSH_AI_PROVIDER_HTTP_CODE"
        response="$REPLY"

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Authentication required (HTTP 401). Set an API key if needed."
                return 1
            elif [[ "$http_code" == "404" ]]; then
                echo "zsh-ai-commands::Error::Endpoint not found (HTTP 404). Check base URL: ${base_url}"
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
            echo "zsh-ai-commands::Error::Failed to connect to server at ${base_url}"
            echo "Make sure your local LLM server is running."
            (( attempt++ ))
            if (( attempt <= max_retries )); then
                echo "Retrying..."
                sleep 2
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

# Parse OpenAI-compatible API response to extract command content
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

# ------------------------------------------------------------------------------
# OPTIONAL FUNCTIONS
# ------------------------------------------------------------------------------

# Dynamically discover available models from the server
# Returns: Model names via REPLY (space-separated)
_zsh_ai_provider_get_models() {
    _zsh_ai_provider_get_base_url
    local base_url="$REPLY"

    local models_response
    models_response=$(curl -s -S --max-time 10 "${base_url}/models" 2>/dev/null)

    if [[ $? -ne 0 || -z "$models_response" ]]; then
        # Return default model if discovery fails
        REPLY="${PROVIDER_MODELS[*]}"
        return 0
    fi

    # Extract model IDs from response
    local models
    models=$(echo "$models_response" | jq -r '.data[].id // .models[].id // empty' 2>/dev/null | tr '\n' ' ')

    if [[ -z "$models" ]]; then
        REPLY="${PROVIDER_MODELS[*]}"
        return 0
    fi

    REPLY="$models"
    return 0
}

# Validate model against dynamically discovered list
# Arguments: $1 = model name
# Returns: 0 if valid, 1 if invalid
_zsh_ai_provider_validate_model_impl() {
    local model="$1"

    # Get available models
    _zsh_ai_provider_get_models
    local available_models=($=REPLY)

    # Check if model is in the list
    local m
    for m in "${available_models[@]}"; do
        if [[ "$m" == "$model" ]]; then
            return 0
        fi
    done

    # For local servers, accept any model (user might know better)
    return 0
}
