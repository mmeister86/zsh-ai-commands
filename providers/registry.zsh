#!/bin/zsh
# ==============================================================================
# Provider Registry
# ==============================================================================
# Manages discovery, loading, and coordination of LLM providers.
# The registry maintains a list of available providers and tracks the currently
# active provider.
# ==============================================================================

# ------------------------------------------------------------------------------
# REGISTRY VARIABLES
# ------------------------------------------------------------------------------

# Name of the currently loaded provider
typeset -g _zsh_ai_registry_current_provider=""

# _zsh_ai_registry_dir must be set by the caller before sourcing this file.
# Fallback for direct sourcing (not recommended):
(( ! ${+_zsh_ai_registry_dir} )) && typeset -g _zsh_ai_registry_dir="${${(%):-%x}:A:h}"

# ------------------------------------------------------------------------------
# PROVIDER MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

# Load a provider module and set it as current
# Arguments: $1 = provider name
# Returns: 0 on success, 1 on failure
_zsh_ai_registry_load_provider() {
    local provider_name="$1"

    if [[ -z "$provider_name" ]]; then
        echo "zsh-ai-commands::Error::No provider name specified"
        return 1
    fi

    # Construct file path directly — avoids associative array scoping issues
    local provider_file="${_zsh_ai_registry_dir}/${provider_name}.zsh"

    if [[ ! -f "$provider_file" ]]; then
        echo "zsh-ai-commands::Error::Unknown provider: $provider_name"
        _zsh_ai_registry_list_providers
        echo "Available providers: $REPLY"
        return 1
    fi

    # Clear optional provider hooks so old provider functions do not leak
    unfunction _zsh_ai_provider_get_models 2>/dev/null
    unfunction _zsh_ai_provider_validate_model_impl 2>/dev/null
    unfunction _zsh_ai_provider_transform_request 2>/dev/null

    # Source the provider file
    source "$provider_file"

    if [[ -z "$PROVIDER_NAME" ]]; then
        echo "zsh-ai-commands::Error::Provider $provider_name did not set PROVIDER_NAME"
        return 1
    fi

    _zsh_ai_registry_current_provider="$provider_name"
    return 0
}

# List all available provider names
# Returns: Provider names via REPLY variable (space-separated)
_zsh_ai_registry_list_providers() {
    local f name names=()
    for f in "${_zsh_ai_registry_dir}"/*.zsh(N); do
        name="${f:t:r}"
        [[ "$name" == "_provider_interface" || "$name" == "registry" || "$name" == "_common" ]] && continue
        names+=("$name")
    done
    REPLY="${names[*]}"
    return 0
}

# Get the current provider name
# Returns: Current provider name via REPLY variable
_zsh_ai_registry_get_current_provider() {
    REPLY="$_zsh_ai_registry_current_provider"
    return 0
}

# Get available models for the current provider
# Returns: Model names via REPLY variable (newline-separated)
# Returns: 0 on success, 1 if no provider loaded
_zsh_ai_registry_get_provider_models() {
    if [[ -z "$_zsh_ai_registry_current_provider" ]]; then
        echo "zsh-ai-commands::Error::No provider loaded"
        return 1
    fi

    # Check if provider has a custom get_models function
    if (( ${+functions[_zsh_ai_provider_get_models]} )); then
        _zsh_ai_provider_get_models
        return $?
    fi

    # Fall back to PROVIDER_MODELS array
    if (( ${#PROVIDER_MODELS} > 0 )); then
        REPLY="${(F)PROVIDER_MODELS}"
        return 0
    fi

    echo "zsh-ai-commands::Error::No models available for provider: $_zsh_ai_registry_current_provider"
    return 1
}

# Get display name for the current provider
# Returns: Display name via REPLY variable
# Returns: 0 on success, 1 if no provider loaded
_zsh_ai_registry_get_provider_display_name() {
    if [[ -z "$_zsh_ai_registry_current_provider" ]]; then
        echo "zsh-ai-commands::Error::No provider loaded"
        return 1
    fi

    REPLY="$PROVIDER_DISPLAY_NAME"
    return 0
}

# Wrapper for _zsh_ai_registry_get_provider_display_name
# Returns: Display name via REPLY variable
_zsh_ai_registry_get_display_name() {
    _zsh_ai_registry_get_provider_display_name
    return $?
}

# ------------------------------------------------------------------------------
# MODEL MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

# Get the model from config or environment variable with fallback to default
# Returns: Model name via REPLY variable
# Returns: 0 on success, 1 if no provider loaded
_zsh_ai_provider_get_model() {
    if [[ -z "$_zsh_ai_registry_current_provider" ]]; then
        echo "zsh-ai-commands::Error::No provider loaded"
        return 1
    fi

    local model=""

    # Check config file first
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        model=$(grep -E "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \n\r')
    fi

    # Fall back to environment variable
    if [[ -z "$model" && -n "$ZSH_AI_COMMANDS_LLM_NAME" ]]; then
        model="$ZSH_AI_COMMANDS_LLM_NAME"
    fi

    # Fall back to provider default
    if [[ -z "$model" ]]; then
        model="$PROVIDER_DEFAULT_MODEL"
    fi

    REPLY="$model"
    return 0
}

# Validate that a model is supported by the current provider
# Arguments: $1 = model name (optional, uses current model if not specified)
# Returns: 0 if valid, 1 if invalid or no provider loaded
_zsh_ai_provider_validate_model() {
    local model="${1:-}"

    if [[ -z "$_zsh_ai_registry_current_provider" ]]; then
        echo "zsh-ai-commands::Error::No provider loaded"
        return 1
    fi

    # If no model specified, get current model
    if [[ -z "$model" ]]; then
        _zsh_ai_provider_get_model || return 1
        model="$REPLY"
    fi

    # Check if provider has a custom validate_model hook
    if (( ${+functions[_zsh_ai_provider_validate_model_impl]} )); then
        _zsh_ai_provider_validate_model_impl "$model"
        return $?
    fi

    # Default validation: check against PROVIDER_MODELS array
    local valid_model=""
    for valid_model in "${PROVIDER_MODELS[@]}"; do
        if [[ "$valid_model" == "$model" ]]; then
            return 0
        fi
    done

    echo "zsh-ai-commands::Error::Model '$model' is not supported by provider '$_zsh_ai_registry_current_provider'"
    echo "Supported models: ${(j:, :)PROVIDER_MODELS}"
    return 1
}

# Get the default model for the current provider
# Returns: Default model name via REPLY variable
# Returns: 0 on success, 1 if no provider loaded
_zsh_ai_provider_get_default_model() {
    if [[ -z "$_zsh_ai_registry_current_provider" ]]; then
        echo "zsh-ai-commands::Error::No provider loaded"
        return 1
    fi

    REPLY="$PROVIDER_DEFAULT_MODEL"
    return 0
}

# ------------------------------------------------------------------------------
# REQUEST TRANSFORMATION
# ------------------------------------------------------------------------------

# Transform a request from OpenAI format to provider-specific format
# This function allows providers to modify the request body before sending
# Arguments: $1 = provider name, $2 = request body (JSON), $3 = model name
# Returns: Transformed request body via REPLY variable
# Returns: 0 on success, 1 on failure
_zsh_ai_registry_configure_from_openai_format() {
    local provider_name="$1"
    local request_body="$2"
    local model="$3"

    # Ensure provider is loaded
    if [[ "$_zsh_ai_registry_current_provider" != "$provider_name" ]]; then
        _zsh_ai_registry_load_provider "$provider_name" || return 1
    fi

    # Check if provider has a custom format transformation function
    if (( ${+functions[_zsh_ai_provider_transform_request]} )); then
        _zsh_ai_provider_transform_request "$request_body" "$model"
        return $?
    fi

    # Default: return the request body unchanged (OpenAI format)
    REPLY="$request_body"
    return 0
}

# ------------------------------------------------------------------------------
# INITIALIZATION
# ------------------------------------------------------------------------------

# Auto-discover providers when registry is loaded
