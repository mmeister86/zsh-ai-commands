#!/bin/zsh
# ==============================================================================
# LLM Provider Interface Documentation
# ==============================================================================
# This file documents the interface that all LLM providers must implement.
# Each provider is a self-contained .zsh file that declares configuration
# variables and implements the functions defined below.
#
# Provider files are named: providers/<provider_name>.zsh
# Example: providers/openai.zsh, providers/anthropic.zsh, providers/ollama.zsh
#
# ==============================================================================

# ------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ------------------------------------------------------------------------------
# Each provider MUST declare the following variables at load time:
#
# 1. PROVIDER_NAME
#    Description: Unique identifier for this provider (lowercase, no spaces)
#    Example:
#        typeset -g PROVIDER_NAME="openai"
#
# 2. PROVIDER_DISPLAY_NAME
#    Description: Human-readable name for display purposes
#    Example:
#        typeset -g PROVIDER_DISPLAY_NAME="OpenAI"
#
# 3. PROVIDER_API_BASE
#    Description: Base URL for the provider's API
#    Example:
#        typeset -g PROVIDER_API_BASE="https://api.openai.com/v1"
#
# 4. PROVIDER_MODELS
#    Description: Array of supported model identifiers
#    Example:
#        typeset -ga PROVIDER_MODELS=("gpt-4o" "gpt-4o-mini" "gpt-4-turbo")
#
# 5. PROVIDER_DEFAULT_MODEL
#    Description: Default model to use if none specified
#    Example:
#        typeset -g PROVIDER_DEFAULT_MODEL="gpt-4o-mini"
#
# 6. PROVIDER_REQUIRES_API_KEY
#    Description: Whether this provider requires an API key (true/false)
#    Example:
#        typeset -g PROVIDER_REQUIRES_API_KEY=true
#
# 7. PROVIDER_KEY_ENV_VAR
#    Description: Environment variable name for the API key
#    Example:
#        typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_OPENAI_API_KEY"
#
# 8. PROVIDER_KEY_FILE
#    Description: Filename for storing the API key (relative to config dir)
#    Example:
#        typeset -g PROVIDER_KEY_FILE="openai_key"

# ------------------------------------------------------------------------------
# REQUIRED FUNCTIONS
# ------------------------------------------------------------------------------
# Each provider MUST implement the following functions:
#
# 1. _zsh_ai_provider_get_api_key
#    Description: Retrieves the API key for this provider
#    Returns: API key string via REPLY variable
#    Returns: 0 on success, 1 if no key is available
#    Example:
#        _zsh_ai_provider_get_api_key() {
#            local key_file="$ZSH_AI_COMMANDS_CONFIG_DIR/$PROVIDER_KEY_FILE"
#            if [[ -f "$key_file" ]]; then
#                REPLY=$(head -n1 "$key_file" | tr -d '\n\r')
#                return 0
#            fi
#            return 1
#        }
#
# 2. _zsh_ai_provider_make_request
#    Arguments: $1 = user prompt, $2 = model name, $3 = n_generations, $4 = explainer (true/false)
#    Description: Makes the API request to the provider
#    Returns: Raw response body via REPLY variable
#    Returns: 0 on success, 1 on failure
#    Example:
#        _zsh_ai_provider_make_request() {
#            local prompt="$1" model="$2" n="$3" explainer="$4"
#            # Build request, make API call, return response in REPLY
#            return 0
#        }
#
# 3. _zsh_ai_provider_parse_response
#    Arguments: $1 = raw API response body
#    Description: Parses the provider-specific response format
#    Returns: Extracted commands via REPLY variable (newline-separated for multiple choices)
#    Returns: 0 on success, 1 on failure
#    Example:
#        _zsh_ai_provider_parse_response() {
#            local response="$1"
#            REPLY=$(echo "$response" | jq -r '.choices[].message.content')
#            return 0
#        }

# ------------------------------------------------------------------------------
# OPTIONAL FUNCTIONS
# ------------------------------------------------------------------------------
# Providers MAY implement these functions for additional functionality:
#
# 1. _zsh_ai_provider_get_models
#    Description: Returns available models (overrides PROVIDER_MODELS for dynamic discovery)
#    Returns: Model names via REPLY (newline-separated or array)
#    Default: Uses PROVIDER_MODELS variable if not implemented
#
# 2. _zsh_ai_provider_validate_model
#    Arguments: $1 = model name
#    Description: Validates that a model is supported by this provider
#    Returns: 0 if valid, 1 if invalid
#    Default: Checks against PROVIDER_MODELS array if not implemented

# ------------------------------------------------------------------------------
# GLOBAL VARIABLES AVAILABLE TO PROVIDERS
# ------------------------------------------------------------------------------
# Providers can rely on these global variables being set:
#
# - ZSH_AI_COMMANDS_CONFIG_DIR     : Path to config directory (~/.config/zsh-ai-commands)
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
# 8. Clean up any temporary files created during requests

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
#   # Required Variables
#   typeset -g PROVIDER_NAME="my-provider"
#   typeset -g PROVIDER_DISPLAY_NAME="My Provider"
#   typeset -g PROVIDER_API_BASE="https://api.myprovider.com/v1"
#   typeset -ga PROVIDER_MODELS=("model-1" "model-2")
#   typeset -g PROVIDER_DEFAULT_MODEL="model-1"
#   typeset -g PROVIDER_REQUIRES_API_KEY=true
#   typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_MY_PROVIDER_API_KEY"
#   typeset -g PROVIDER_KEY_FILE="my_provider_key"
#
#   # Required Functions
#   _zsh_ai_provider_get_api_key() {
#       local key_file="$ZSH_AI_COMMANDS_CONFIG_DIR/$PROVIDER_KEY_FILE"
#       if [[ -f "$key_file" ]]; then
#           REPLY=$(head -n1 "$key_file" | tr -d '\n\r')
#           return 0
#       fi
#       return 1
#   }
#
#   _zsh_ai_provider_make_request() {
#       local prompt="$1" model="$2" n="$3" explainer="$4"
#       # Build request body, make API call
#       # Store raw response in REPLY
#       return 0
#   }
#
#   _zsh_ai_provider_parse_response() {
#       local response="$1"
#       REPLY=$(echo "$response" | jq -r '.choices[].message.content')
#       return 0
#   }
