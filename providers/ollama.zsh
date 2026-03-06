#!/bin/zsh
# ==============================================================================
# Provider: Ollama (Local)
# ==============================================================================
# Implements the Ollama API provider for zsh-ai-commands.
# Supports local LLM inference via Ollama server.
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------

typeset -g PROVIDER_NAME="ollama"
typeset -g PROVIDER_DISPLAY_NAME="Ollama (Local)"
typeset -g PROVIDER_API_BASE="${ZSH_AI_COMMANDS_OLLAMA_HOST:-http://localhost:11434}"
typeset -ga PROVIDER_MODELS=()  # Dynamically loaded via _zsh_ai_provider_get_models
typeset -g PROVIDER_DEFAULT_MODEL=""
typeset -g PROVIDER_REQUIRES_API_KEY=false
typeset -g PROVIDER_KEY_ENV_VAR=""
typeset -g PROVIDER_KEY_FILE=""

# ------------------------------------------------------------------------------
# REQUIRED FUNCTIONS
# ------------------------------------------------------------------------------

# Get API key - Not required for Ollama
# Returns: Always succeeds with empty string
# Returns: 0 always (Ollama doesn't require API keys)
_zsh_ai_provider_get_api_key() {
    REPLY=""
    return 0
}

# Make API request to Ollama /api/chat endpoint
# Arguments: $1 = request body (JSON string)
# Returns: Raw response via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_make_request() {
    local request_body="$1"
    local max_retries=2
    local timeout="${ZSH_AI_COMMANDS_TIMEOUT:-60}"
    local attempt=0
    local response=""
    local http_code=""

    # Use the configured Ollama host
    local api_base="${ZSH_AI_COMMANDS_OLLAMA_HOST:-http://localhost:11434}"

    while (( attempt <= max_retries )); do
        response=$(curl -s -S \
            --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${api_base}/api/chat" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "404" ]]; then
                echo "zsh-ai-commands::Error::Model not found (HTTP 404). Check if the model is pulled: ollama pull <model>"
                return 1
            elif [[ "$http_code" == "500" || "$http_code" == "502" || "$http_code" == "503" ]]; then
                local retry_after=$((2 ** attempt))
                echo "zsh-ai-commands::Error::Server error (HTTP $http_code). Retrying in ${retry_after} seconds..."
                sleep "$retry_after"
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::API request failed with HTTP $http_code"
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
            echo "zsh-ai-commands::Error::Failed to connect to Ollama server at ${api_base}"
            echo "Make sure Ollama is running: ollama serve"
            return 1
        else
            echo "zsh-ai-commands::Error::curl failed with exit code $curl_exit"
            return 1
        fi
    done

    echo "zsh-ai-commands::Error::Max retries ($max_retries) exceeded"
    return 1
}

# Parse Ollama API response to extract command content
# Arguments: $1 = raw API response body
# Returns: Extracted commands via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    # Extract content from message.content
    parsed=$(echo "$response" | jq -r '.message.content' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        # Check for API error message
        local error_msg=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::API error: $error_msg"
            return 1
        fi

        echo "zsh-ai-commands::Error::Failed to parse API response"
        return 1
    fi

    REPLY="$parsed"
    return 0
}

# ------------------------------------------------------------------------------
# OPTIONAL FUNCTIONS
# ------------------------------------------------------------------------------

# Fetch available models from Ollama server
# Returns: Model names via REPLY (newline-separated)
# Returns: 0 on success, 1 on failure
_zsh_ai_provider_get_models() {
    local api_base="${ZSH_AI_COMMANDS_OLLAMA_HOST:-http://localhost:11434}"
    local response=""
    local models=""

    response=$(curl -s -S --max-time 10 "${api_base}/api/tags" 2>&1)
    local curl_exit=$?

    if (( curl_exit != 0 )); then
        # Return empty list if Ollama is not running
        REPLY=""
        return 1
    fi

    # Extract model names from response
    models=$(echo "$response" | jq -r '.models[].name' 2>/dev/null)

    if [[ -z "$models" || "$models" == "null" ]]; then
        REPLY=""
        return 1
    fi

    REPLY="$models"
    return 0
}

# Validate that a model is available
# Arguments: $1 = model name
# Returns: 0 if valid, 1 if invalid
_zsh_ai_provider_validate_model() {
    local model="$1"

    # Get available models
    _zsh_ai_provider_get_models
    local available_models="$REPLY"

    if [[ -z "$available_models" ]]; then
        # If we can't get models, allow any model (Ollama might auto-pull)
        return 0
    fi

    # Check if model is in the list (exact match or prefix match)
    if echo "$available_models" | grep -qF "$model"; then
        return 0
    fi

    # Also check for model without tag (e.g., "llama2" matches "llama2:latest")
    local model_base="${model%%:*}"
    if echo "$available_models" | grep -q "^${model_base}:"; then
        return 0
    fi

    return 1
}
