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

# Associative array mapping provider names to their file paths
typeset -gA _zsh_ai_registry_providers=()

# Name of the currently loaded provider
typeset -g _zsh_ai_registry_current_provider=""

# ------------------------------------------------------------------------------
# REGISTRY INITIALIZATION
# ------------------------------------------------------------------------------

# Discover and register all available providers
# This function scans the providers directory for .zsh files
# Returns: 0 on success
_zsh_ai_registry_discover_providers() {
    local providers_dir="${0:A:h}"
    local provider_file=""

    _zsh_ai_registry_providers=()

    # Scan for provider files (excluding _provider_interface.zsh and registry.zsh)
    for provider_file in "$providers_dir"/*.zsh(N); do
        local basename="${provider_file:t}"

        # Skip interface documentation and registry itself
        [[ "$basename" == "_provider_interface.zsh" ]] && continue
        [[ "$basename" == "registry.zsh" ]] && continue

        # Extract provider name from filename (without .zsh extension)
        local provider_name="${basename%.zsh}"

        # Register the provider
        _zsh_ai_registry_providers["$provider_name"]="$provider_file"
    done

    return 0
}

# ------------------------------------------------------------------------------
# PROVIDER MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------

# Load a provider module and set it as current
# Arguments: $1 = provider name
# Returns: 0 on success, 1 on failure
_zsh_ai_registry_load_provider() {
    local provider_name="$1"

    # Validate provider name
    if [[ -z "$provider_name" ]]; then
        echo "zsh-ai-commands::Error::No provider name specified"
        return 1
    fi

    # Discover providers if not already done
    if (( ${#_zsh_ai_registry_providers} == 0 )); then
        _zsh_ai_registry_discover_providers
    fi

    # Check if provider exists
    if [[ -z "${_zsh_ai_registry_providers[$provider_name]}" ]]; then
        echo "zsh-ai-commands::Error::Unknown provider: $provider_name"
        echo "Available providers: ${(@k)_zsh_ai_registry_providers}"
        return 1
    fi

    local provider_file="${_zsh_ai_registry_providers[$provider_name]}"

    # Check if file exists
    if [[ ! -f "$provider_file" ]]; then
        echo "zsh-ai-commands::Error::Provider file not found: $provider_file"
        return 1
    fi

    # Source the provider file
    source "$provider_file"

    # Verify required variables are set
    if [[ -z "$PROVIDER_NAME" ]]; then
        echo "zsh-ai-commands::Error::Provider $provider_name did not set PROVIDER_NAME"
        return 1
    fi

    # Set as current provider
    _zsh_ai_registry_current_provider="$provider_name"

    return 0
}

# List all available provider names
# Returns: Provider names via REPLY variable (space-separated)
_zsh_ai_registry_list_providers() {
    # Discover providers if not already done
    if (( ${#_zsh_ai_registry_providers} == 0 )); then
        _zsh_ai_registry_discover_providers
    fi

    REPLY="${(@k)_zsh_ai_registry_providers}"
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

    # Check if provider has a custom validate_model function
    if (( ${+functions[_zsh_ai_provider_validate_model]} )); then
        _zsh_ai_provider_validate_model "$model"
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
_zsh_ai_registry_discover_providers
