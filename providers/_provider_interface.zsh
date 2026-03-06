#!/bin/zsh
# ==============================================================================
# LLM Provider Interface Documentation
# ==============================================================================
# This file documents the interface that all LLM providers must implement.
# Each provider is a self-contained .zsh file that implements the functions
# defined below.
#
# Provider files are named: providers/<provider_name>.zsh
# Example: providers/openai.zsh, providers/anthropic.zsh, providers/ollama.zsh
#
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED FUNCTIONS
# ------------------------------------------------------------------------------
# Each provider MUST implement the following functions:
#
# 1. _zsh_ai_provider_name
#    Description: Returns the unique identifier/name for this provider
#    Returns: Provider name string via REPLY variable
#    Example:
#        _zsh_ai_provider_name() {
#            REPLY="openai"
#            return 0
#        }
#
# 2. _zsh_ai_provider_models
#    Description: Returns an array of supported model names for this provider
#    Returns: Model names via REPLY (newline-separated or array)
#    Example:
#        _zsh_ai_provider_models() {
#            REPLY=("gpt-4o" "gpt-4o-mini" "gpt-4-turbo")
#            return 0
#        }
#
# 3. _zsh_ai_provider_get_api_key
#    Description: Retrieves the API key for this provider
#    Returns: API key string via REPLY variable
#    Returns: 0 on success, 1 if no key is available
#    Example:
#        _zsh_ai_provider_get_api_key() {
#            local key_file="$ZSH_AI_COMMANDS_CONFIG_DIR/openai_api_key"
#            if [[ -f "$key_file" ]]; then
#                REPLY=$(head -n1 "$key_file" | tr -d '\n\r')
#                return 0
#            fi
#            return 1
#        }
#
# 4. _zsh_ai_provider_setup_curl_config
#    Arguments: $1 = API key
#    Description: Sets up curl configuration for this provider's API
#    Returns: 0 on success, 1 on failure
#    Notes: Should create a curl config file and set ZSH_AI_COMMANDS_CURL_CONFIG_FILE
#    Example:
#        _zsh_ai_provider_setup_curl_config() {
#            local api_key="$1"
#            cat > "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE" << EOF
#        header = "Content-Type: application/json"
#        header = "Authorization: Bearer ${api_key}"
#        silent
#        EOF
#            return 0
#        }
#
# 5. _zsh_ai_provider_build_request
#    Arguments: $1 = user prompt, $2 = model name, $3 = n_generations, $4 = explainer (true/false)
#    Description: Builds the JSON request body for the API call
#    Returns: JSON string via REPLY variable
#    Example:
#        _zsh_ai_provider_build_request() {
#            local prompt="$1" model="$2" n="$3" explainer="$4"
#            # Build and return JSON in REPLY
#            REPLY='{"model": "'$model'", "messages": [...]}'
#            return 0
#        }
#
# 6. _zsh_ai_provider_get_api_url
#    Description: Returns the API endpoint URL for this provider
#    Returns: URL string via REPLY variable
#    Example:
#        _zsh_ai_provider_get_api_url() {
#            REPLY="https://api.openai.com/v1/chat/completions"
#            return 0
#        }
#
# 7. _zsh_ai_provider_parse_response
#    Arguments: $1 = raw API response body
#    Description: Parses the provider-specific response format
#    Returns: Extracted content via REPLY variable (newline-separated for multiple choices)
#    Returns: 0 on success, 1 on failure
#    Example:
#        _zsh_ai_provider_parse_response() {
#            local response="$1"
#            REPLY=$(echo "$response" | jq -r '.choices[].message.content')
#            return 0
#        }
#
# 8. _zsh_ai_provider_validate_response
#    Arguments: $1 = raw API response body, $2 = HTTP status code
#    Description: Validates the response and handles provider-specific errors
#    Returns: 0 if response is valid, 1 if there's an error
#    Notes: Should output error messages to stdout on failure
#    Example:
#        _zsh_ai_provider_validate_response() {
#            local response="$1" http_code="$2"
#            if [[ "$http_code" != "200" ]]; then
#                echo "API error: HTTP $http_code"
#                return 1
#            fi
#            return 0
#        }
#
# 9. _zsh_ai_provider_cleanup
#    Description: Cleans up any resources created by this provider
#    Returns: Always returns 0
#    Example:
#        _zsh_ai_provider_cleanup() {
#            [[ -f "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE" ]] && rm -f "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE"
#            return 0
#        }
#
# 10. _zsh_ai_provider_init
#     Description: Initializes the provider (validates API key, sets defaults)
#     Returns: 0 on success, 1 on failure
#     Example:
#         _zsh_ai_provider_init() {
#             _zsh_ai_provider_get_api_key || return 1
#             _zsh_ai_provider_setup_curl_config "$REPLY" || return 1
#             return 0
#         }

# ------------------------------------------------------------------------------
# OPTIONAL FUNCTIONS
# ------------------------------------------------------------------------------
# Providers MAY implement these functions for additional functionality:
#
# 1. _zsh_ai_provider_get_default_model
#    Description: Returns the default model to use for this provider
#    Returns: Model name via REPLY variable
#    Default: First model from _zsh_ai_provider_models if not implemented
#
# 2. _zsh_ai_provider_get_system_prompt
#    Arguments: $1 = explainer mode (true/false)
#    Description: Returns the system prompt to use for this provider
#    Returns: System prompt string via REPLY variable
#    Default: Generic shell command prompt if not implemented
#
# 3. _zsh_ai_provider_format_error
#    Arguments: $1 = HTTP code, $2 = response body
#    Description: Formats provider-specific error messages
#    Returns: Formatted error string via REPLY variable
#    Default: Generic error format if not implemented

# ------------------------------------------------------------------------------
# GLOBAL VARIABLES AVAILABLE TO PROVIDERS
# ------------------------------------------------------------------------------
# Providers can rely on these global variables being set:
#
# - ZSH_AI_COMMANDS_CONFIG_DIR     : Path to config directory (~/.config/zsh-ai-commands)
# - ZSH_AI_COMMANDS_CURL_CONFIG_FILE : Path to curl config file (provider should set this)
# - ZSH_AI_COMMANDS_DEBUG          : If "true", debug logging is enabled
# - ZSH_AI_COMMANDS_LLM_NAME       : Currently selected model name
# - ZSH_AI_COMMANDS_N_GENERATIONS  : Number of completions to request
# - ZSH_AI_COMMANDS_EXPLAINER      : If "true", include command explanations
# - ZSH_AI_COMMANDS_TIMEOUT        : Request timeout in seconds (default: 30)

# ------------------------------------------------------------------------------
# NAMING CONVENTIONS
# ------------------------------------------------------------------------------
# - All provider functions MUST be prefixed with _zsh_ai_provider_
# - Provider files should be named: <provider_name>.zsh (lowercase)
# - Provider names should be simple identifiers: alphanumeric, lowercase, hyphens allowed
# - Avoid using special characters or spaces in provider names

# ------------------------------------------------------------------------------
# IMPLEMENTATION NOTES
# ------------------------------------------------------------------------------
# 1. Providers should be self-contained and not depend on other providers
# 2. Use the REPLY variable for return values (avoids subshell overhead)
# 3. Return 0 for success, non-zero for failure
# 4. Output error messages to stdout (they will be displayed to the user)
# 5. Use _zsh_ai_commands_log for debug logging
# 6. Handle API rate limits and retries appropriately
# 7. Ensure sensitive data (API keys) are handled securely (file permissions: 600)
# 8. Clean up temporary files in the cleanup function

# ------------------------------------------------------------------------------
# EXAMPLE: Minimal Provider Implementation
# ------------------------------------------------------------------------------
# See openai.zsh for a complete reference implementation.
#
# Minimal structure:
#
#   #!/bin/zsh
#   # Provider: my-provider
#
#   _zsh_ai_provider_name() {
#       REPLY="my-provider"
#       return 0
#   }
#
#   _zsh_ai_provider_models() {
#       REPLY=("model-1" "model-2")
#       return 0
#   }
#
#   _zsh_ai_provider_get_api_key() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_setup_curl_config() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_build_request() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_get_api_url() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_parse_response() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_validate_response() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_cleanup() {
#       # Implementation
#   }
#
#   _zsh_ai_provider_init() {
#       # Implementation
#   }
