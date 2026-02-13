#!/bin/zsh

typeset -g ZSH_AI_COMMANDS_CONFIG_DIR="${HOME}/.config/zsh-ai-commands"
typeset -g ZSH_AI_COMMANDS_API_KEY_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/api_key"
typeset -g ZSH_AI_COMMANDS_CONFIG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/config"
typeset -g ZSH_AI_COMMANDS_CURL_CONFIG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/.curl_config"
typeset -g ZSH_AI_COMMANDS_LOG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/debug.log"
typeset -ga ZSH_AI_COMMANDS_SUPPORTED_MODELS=("gpt-4o" "gpt-4o-mini" "gpt-4-turbo" "gpt-4" "gpt-3.5-turbo")

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
    return 0
}

_zsh_ai_commands_log() {
    local message="$1"
    (( ${+ZSH_AI_COMMANDS_DEBUG} )) && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$ZSH_AI_COMMANDS_LOG_FILE"
}

_zsh_ai_commands_get_api_key() {
    local api_key=""
    
    if [[ -f "$ZSH_AI_COMMANDS_API_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_API_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        _zsh_ai_commands_log "API key loaded from file"
    fi
    
    if [[ -z "$api_key" && -n "$ZSH_AI_COMMANDS_OPENAI_API_KEY" ]]; then
        api_key="$ZSH_AI_COMMANDS_OPENAI_API_KEY"
        _zsh_ai_commands_log "API key loaded from environment variable"
    fi
    
    if [[ -z "$api_key" ]]; then
        return 1
    fi
    
    REPLY="$api_key"
    return 0
}

_zsh_ai_commands_setup_curl_config() {
    local api_key="$1"
    _zsh_ai_commands_ensure_config_dir || return 1
    
    cat > "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE" << EOF
header = "Content-Type: application/json"
header = "Authorization: Bearer ${api_key}"
silent
EOF
    chmod 600 "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE"
    return 0
}

_zsh_ai_commands_cleanup_curl_config() {
    [[ -f "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE" ]] && rm -f "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE"
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
        model="gpt-4o"
    fi
    
    REPLY="$model"
    return 0
}

_zsh_ai_commands_set_llm_model() {
    _zsh_ai_commands_ensure_config_dir || return 1
    
    local selected_model=$(printf '%s\n' "${ZSH_AI_COMMANDS_SUPPORTED_MODELS[@]}" | fzf --reverse --height=~50% --prompt="Select LLM Model: " --header="Choose the OpenAI model to use")
    
    if [[ -n "$selected_model" ]]; then
        if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
            if grep -q "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE"; then
                sed -i '' "s/^LLM_MODEL=.*/LLM_MODEL=${selected_model}/" "$ZSH_AI_COMMANDS_CONFIG_FILE"
            else
                echo "LLM_MODEL=${selected_model}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
            fi
        else
            echo "LLM_MODEL=${selected_model}" > "$ZSH_AI_COMMANDS_CONFIG_FILE"
        fi
        ZSH_AI_COMMANDS_LLM_NAME="$selected_model"
        echo "Model set to: $selected_model"
    fi
}

_zsh_ai_commands_make_request() {
    local request_body="$1"
    local max_retries=2
    local timeout=30
    local attempt=0
    local response=""
    local http_code=""
    
    while (( attempt <= max_retries )); do
        _zsh_ai_commands_log "API request attempt $((attempt + 1))"
        
        response=$(curl -q --config "$ZSH_AI_COMMANDS_CURL_CONFIG_FILE" \
            --max-time "$timeout" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "https://api.openai.com/v1/chat/completions" 2>&1)
        local curl_exit=$?
        
        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')
        
        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying in 2 seconds..."
                sleep 2
                (( attempt++ ))
                continue
            elif [[ "$http_code" == "500" || "$http_code" == "502" || "$http_code" == "503" ]]; then
                echo "zsh-ai-commands::Error::Server error (HTTP $http_code). Retrying in 2 seconds..."
                sleep 2
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::API request failed with HTTP $http_code"
                _zsh_ai_commands_log "API error response: $response"
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

_zsh_ai_commands_parse_response() {
    local response="$1"
    local parsed=""
    
    parsed=$(echo "$response" | jq -r '.choices[].message.content' 2>/dev/null)
    
    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::API error: $error_msg"
            return 1
        fi
        
        parsed=$(echo "$response" | sed '/"content": "/ s/\\/\\\\/g' | jq -r '.choices[].message.content' 2>/dev/null)
        
        if [[ -z "$parsed" || "$parsed" == "null" ]]; then
            echo "zsh-ai-commands::Error::Failed to parse API response"
            _zsh_ai_commands_log "Unparseable response: $response"
            return 1
        fi
    fi
    
    REPLY=$(echo "$parsed" | uniq)
    return 0
}

select_llm_model() {
    _zsh_ai_commands_set_llm_model
    zle reset-prompt
}
zle -N select_llm_model

_zsh_ai_commands_init() {
    _zsh_ai_commands_check_dependencies || return 1
    _zsh_ai_commands_ensure_config_dir || return 1
    
    _zsh_ai_commands_get_api_key || {
        echo "zsh-ai-commands::Error::No API key found."
        echo "Please either:"
        echo "  1. Create $ZSH_AI_COMMANDS_API_KEY_FILE with your API key"
        echo "  2. Set ZSH_AI_COMMANDS_OPENAI_API_KEY environment variable"
        return 1
    }
    local api_key="$REPLY"
    _zsh_ai_commands_setup_curl_config "$api_key" || return 1
    
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
    
    BUFFER="Asking $ZSH_AI_COMMANDS_LLM_NAME for a command to do: $user_query. Please wait..."
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
    
    _zsh_ai_commands_make_request "$request_body" || { ret=$?; return $ret }
    local response="$REPLY"
    
    _zsh_ai_commands_parse_response "$response" || { ret=$?; return $ret }
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

_zsh_ai_commands_init || { 
    _zsh_ai_commands_cleanup_curl_config
    return 1 
}

bindkey "$ZSH_AI_COMMANDS_HOTKEY" fzf_ai_commands

autoload -U add-zsh-hook
_zsh_ai_commands_cleanup_hook() {
    _zsh_ai_commands_cleanup_curl_config
}
add-zsh-hook zshexit _zsh_ai_commands_cleanup_hook
