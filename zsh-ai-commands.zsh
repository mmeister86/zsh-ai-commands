#!/bin/zsh

typeset -g _ZSH_AI_COMMANDS_DIR="${${(%):-%x}:A:h}"
typeset -g ZSH_AI_COMMANDS_CONFIG_DIR="${HOME}/.config/zsh-ai-commands"
typeset -g ZSH_AI_COMMANDS_API_KEY_DIR="${ZSH_AI_COMMANDS_CONFIG_DIR}/keys"
typeset -g ZSH_AI_COMMANDS_CONFIG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/config"
typeset -g ZSH_AI_COMMANDS_LOG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/debug.log"

_zsh_ai_commands_check_dependencies() {
    local missing=()
    (( ! $+commands[curl] )) && missing+="curl"
    (( ! $+commands[jq] )) && missing+="jq"
    (( ! $+commands[fzf] )) && missing+="fzf"

    if (( ${#missing} > 0 )); then
        echo "zsh-ai-commands::Error::Missing required tools: ${missing[*]}"
        echo "Please install: brew install ${missing[*]}"
        return 1
    fi
    return 0
}

_zsh_ai_commands_ensure_config_dir() {
    if [[ ! -d "$ZSH_AI_COMMANDS_CONFIG_DIR" ]]; then
        mkdir -p "$ZSH_AI_COMMANDS_CONFIG_DIR" 2>/dev/null || {
            echo "zsh-ai-commands::Error::Could not create config directory: $ZSH_AI_COMMANDS_CONFIG_DIR"
            return 1
        }
        chmod 700 "$ZSH_AI_COMMANDS_CONFIG_DIR"
    fi

    # Create keys directory if it doesn't exist
    if [[ ! -d "$ZSH_AI_COMMANDS_API_KEY_DIR" ]]; then
        mkdir -p "$ZSH_AI_COMMANDS_API_KEY_DIR" 2>/dev/null || {
            echo "zsh-ai-commands::Error::Could not create keys directory: $ZSH_AI_COMMANDS_API_KEY_DIR"
            return 1
        }
        chmod 700 "$ZSH_AI_COMMANDS_API_KEY_DIR"
    fi

    # Migrate old api_key file to keys/openai_key
    local old_key_file="${ZSH_AI_COMMANDS_CONFIG_DIR}/api_key"
    local new_key_file="${ZSH_AI_COMMANDS_API_KEY_DIR}/openai_key"
    if [[ -f "$old_key_file" && ! -f "$new_key_file" ]]; then
        mv "$old_key_file" "$new_key_file" 2>/dev/null
        chmod 600 "$new_key_file"
    fi

    return 0
}

_zsh_ai_commands_log() {
    local message="$1"
    (( ${+ZSH_AI_COMMANDS_DEBUG} )) && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$ZSH_AI_COMMANDS_LOG_FILE"
}

_zsh_ai_commands_get_llm_model() {
    local model=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        model=$(grep -E "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \n\r')
    fi

    if [[ -z "$model" && -n "$ZSH_AI_COMMANDS_LLM_NAME" ]]; then
        model="$ZSH_AI_COMMANDS_LLM_NAME"
    fi

    if [[ -z "$model" ]]; then
        model="$PROVIDER_DEFAULT_MODEL"
    fi

    REPLY="$model"
    return 0
}

_zsh_ai_commands_set_llm_model() {
    _zsh_ai_commands_ensure_config_dir || return 1

    # First, select provider
    _zsh_ai_registry_list_providers
    local providers=(${=REPLY})

    if (( ${#providers} == 0 )); then
        echo "zsh-ai-commands::Error::No providers available"
        return 1
    fi

    local selected_provider=$(printf '%s\n' "${providers[@]}" | fzf --reverse --height=~50% --prompt="Select Provider: " --header="Choose the LLM provider")

    if [[ -z "$selected_provider" ]]; then
        echo "No provider selected"
        return 1
    fi

    # Load the selected provider
    _zsh_ai_registry_load_provider "$selected_provider" || return 1

    # Get models for the selected provider
    _zsh_ai_registry_get_provider_models || return 1
    local models=(${(f)REPLY})

    if (( ${#models} == 0 )); then
        echo "zsh-ai-commands::Error::No models available for provider: $selected_provider"
        return 1
    fi

    # Select model
    local selected_model=$(printf '%s\n' "${models[@]}" | fzf --reverse --height=~50% --prompt="Select Model: " --header="Choose the model for $selected_provider")

    if [[ -z "$selected_model" ]]; then
        echo "No model selected"
        return 1
    fi

    # Save both PROVIDER and LLM_MODEL to config
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        if grep -q "^PROVIDER=" "$ZSH_AI_COMMANDS_CONFIG_FILE"; then
            sed -i '' "s/^PROVIDER=.*/PROVIDER=${selected_provider}/" "$ZSH_AI_COMMANDS_CONFIG_FILE"
        else
            echo "PROVIDER=${selected_provider}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
        fi
        if grep -q "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE"; then
            sed -i '' "s/^LLM_MODEL=.*/LLM_MODEL=${selected_model}/" "$ZSH_AI_COMMANDS_CONFIG_FILE"
        else
            echo "LLM_MODEL=${selected_model}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
        fi
    else
        echo "PROVIDER=${selected_provider}" > "$ZSH_AI_COMMANDS_CONFIG_FILE"
        echo "LLM_MODEL=${selected_model}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
    fi

    ZSH_AI_COMMANDS_LLM_NAME="$selected_model"
    echo "Provider set to: $selected_provider, Model set to: $selected_model"
}

select_llm_model() {
    _zsh_ai_commands_set_llm_model
    zle reset-prompt
}
zle -N select_llm_model

_zsh_ai_commands_init() {
    _zsh_ai_commands_check_dependencies || return 1
    _zsh_ai_commands_ensure_config_dir || return 1

    # Set providers directory before sourcing registry (so %x fallback is not needed)
    typeset -g _zsh_ai_registry_dir="${_ZSH_AI_COMMANDS_DIR}/providers"

    # Source provider registry
    source "${_ZSH_AI_COMMANDS_DIR}/providers/registry.zsh" || {
        echo "zsh-ai-commands::Error::Could not load provider registry"
        return 1
    }

    # Load provider from config
    local provider_name=""
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        provider_name=$(grep -E "^PROVIDER=" "$ZSH_AI_COMMANDS_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \n\r')
    fi

    # Fall back to openai if no provider configured
    if [[ -z "$provider_name" ]]; then
        provider_name="openai"
    fi

    # Load the provider
    _zsh_ai_registry_load_provider "$provider_name" || {
        echo "zsh-ai-commands::Error::Could not load provider: $provider_name"
        return 1
    }

    # Get API key via provider function
    _zsh_ai_provider_get_api_key || {
        echo "zsh-ai-commands::Error::No API key found for ${PROVIDER_DISPLAY_NAME:-$provider_name} provider."
        echo "Please either:"
        echo "  1. Create ${ZSH_AI_COMMANDS_API_KEY_DIR}/${PROVIDER_KEY_FILE:-${provider_name}_key} with your API key"
        echo "  2. Set ${PROVIDER_KEY_ENV_VAR:-ZSH_AI_COMMANDS_${(U)provider_name}_API_KEY} environment variable"
        return 1
    }

    # Get model from config or provider default
    _zsh_ai_commands_get_llm_model
    ZSH_AI_COMMANDS_LLM_NAME="$REPLY"

    (( ! ${+ZSH_AI_COMMANDS_HOTKEY} )) && typeset -g ZSH_AI_COMMANDS_HOTKEY='^o'
    (( ! ${+ZSH_AI_COMMANDS_LLM_HOTKEY} )) && typeset -g ZSH_AI_COMMANDS_LLM_HOTKEY='^l'
    (( ! ${+ZSH_AI_COMMANDS_N_GENERATIONS} )) && typeset -g ZSH_AI_COMMANDS_N_GENERATIONS=5
    (( ! ${+ZSH_AI_COMMANDS_EXPLAINER} )) && typeset -g ZSH_AI_COMMANDS_EXPLAINER=true
    (( ! ${+ZSH_AI_COMMANDS_HISTORY} )) && typeset -g ZSH_AI_COMMANDS_HISTORY=false

    bindkey "$ZSH_AI_COMMANDS_LLM_HOTKEY" select_llm_model

    return 0
}

fzf_ai_commands() {
    setopt extendedglob
    local ret=0

    [[ -z "$BUFFER" ]] && { echo "Empty prompt"; return 1 }

    BUFFER="$(echo "$BUFFER" | sed 's/^AI_ASK: //g')"
    local user_query="$BUFFER"

    if [[ "$ZSH_AI_COMMANDS_HISTORY" == "true" ]]; then
        echo "AI_ASK: $user_query" >> "$HISTFILE"
        if (( $+commands[atuin] )); then
            local atuin_id=$(atuin history start "AI_ASK: $user_query")
            atuin history end --exit 0 "$atuin_id"
        fi
    fi

    # Get provider display name for status message
    _zsh_ai_registry_get_display_name
    local display_name="${REPLY:-LLM}"

    BUFFER="Asking ${display_name} (${ZSH_AI_COMMANDS_LLM_NAME}) for a command to do: $user_query. Please wait..."
    local escaped_query=$(echo "$user_query" | sed 's/"/\\"/g')
    zle end-of-line
    zle reset-prompt

    local system_prompt user_prompt request_body

    if [[ "$ZSH_AI_COMMANDS_EXPLAINER" == "true" ]]; then
        system_prompt="You only answer 1 appropriate shell one liner that does what the user asks for. The command has to work with the $(basename $SHELL) terminal. Don't wrap your answer in code blocks or anything, dont acknowledge those rules, don't format your answer. Just reply the plaintext command. If your answer uses arguments or flags, you MUST end your shell command with a shell comment starting with ## with a ; separated list of concise explanations about each agument. Don't explain obvious placeholders like <ip> or <serverport> etc. Remember that your whole answer MUST remain a oneliner."
        local example_q="Description of what the command should do: 'list files, sort by descending size'. Give me the appropriate command."
        local example_a="ls -lSr ## -l long listing ; -S sort by file size ; -r reverse order"
        user_prompt="Description of what the command should do: '$escaped_query'. Give me the appropriate command."
        request_body='{
            "model": "'$ZSH_AI_COMMANDS_LLM_NAME'",
            "n": '$ZSH_AI_COMMANDS_N_GENERATIONS',
            "temperature": 1,
            "messages": [
                {"role": "system", "content": "'$system_prompt'"},
                {"role": "user", "content": "'$example_q'"},
                {"role": "assistant", "content": "'$example_a'"},
                {"role": "user", "content": "'$user_prompt'"}
            ]
        }'
    else
        system_prompt="You only answer 1 appropriate shell one liner that does what the user asks for. The command has to work with the $(basename $SHELL) terminal. Don't wrap your answer in anything, dont acknowledge those rules, don't format your answer. Just reply the plaintext command."
        user_prompt="Description of what the command should do:\n'''\n$escaped_query\n'''\nGive me the appropriate command."
        request_body='{
            "model": "'$ZSH_AI_COMMANDS_LLM_NAME'",
            "n": '$ZSH_AI_COMMANDS_N_GENERATIONS',
            "temperature": 1,
            "messages": [
                {"role": "system", "content": "'$system_prompt'"},
                {"role": "user", "content": "'$user_prompt'"}
            ]
        }'
    fi

    echo "$request_body" | jq > /dev/null 2>&1 || { echo "zsh-ai-commands::Error::Invalid JSON in request body"; return 1 }

    # Use provider make_request function
    _zsh_ai_provider_make_request "$request_body" || { ret=$?; return $ret }
    local response="$REPLY"

    # Use provider parse_response function
    _zsh_ai_provider_parse_response "$response" || { ret=$?; return $ret }
    local parsed_response="$REPLY"

    local selected_command

    if [[ "$ZSH_AI_COMMANDS_EXPLAINER" == "true" ]]; then
        local suggestions=$(echo "$parsed_response" | sort | awk -F ' *## ' '!seen[$1]++' -)
        local commands=$(echo "$suggestions" | awk -F " ## " "{print \$1}")
        local comments=$(echo "$suggestions" | awk -F " ## " "{print \$2}")

        export ZSH_AI_COMMANDS_SUGG_COMMENTS
        ZSH_AI_COMMANDS_SUGG_COMMENTS="$comments"
        selected_command=$(echo "$commands" | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo "$ZSH_AI_COMMANDS_SUGG_COMMENTS" | sed -n "$(({n}+1))"p | sed "s/;/\n/g" | sed "s/^\s*//g;s/\s*$//g"')
    else
        selected_command=$(echo "$parsed_response" | fzf --reverse --height=~100% --preview-window down:wrap --preview 'echo {}')
    fi

    BUFFER="$selected_command"
    zle end-of-line
    zle reset-prompt

    return $ret
}

autoload fzf_ai_commands
zle -N fzf_ai_commands

_zsh_ai_commands_init || return 1

bindkey "$ZSH_AI_COMMANDS_HOTKEY" fzf_ai_commands
