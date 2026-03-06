# Multi-Provider LLM Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend zsh-ai-commands to support multiple LLM providers with a Provider Registry pattern, enabling users to choose between OpenAI, Anthropic, Gemini, Groq, DeepSeek, Ollama, and OpenAI-compatible backends.

**Architecture:** Provider modules in `providers/` directory implement the same interface. A registry loads and manages providers. Core logic delegates API calls to the active provider.

**Tech Stack:** Zsh, curl, jq, fzf

---

## Task 1: Create provider interface and directory structure

**Files:**
- Create: `providers/_provider_interface.zsh`

**Step 1: Create providers directory and interface file**

```bash
mkdir -p providers
```

**Step 2: Write provider interface documentation**

```zsh
cat > providers/_provider_interface.zsh << 'EOF'
#!/bin/zsh
# Provider Interface Definition
#
# Each provider module must define these variables:
#
# PROVIDER_NAME           - Unique identifier (e.g., "openai", "anthropic")
# PROVIDER_DISPLAY_NAME   - Human-readable name for UI
# PROVIDER_API_BASE       - Base URL for API
# PROVIDER_MODELS         - Array of supported model IDs
# PROVIDER_DEFAULT_MODEL  - Default model ID
# PROVIDER_REQUIRES_API_KEY - Boolean: true if API key required
# PROVIDER_KEY_ENV_VAR    - Environment variable name for API key
# PROVIDER_KEY_FILE       - Filename for API key in config/keys/
#
# Each provider must implement these functions:
#
# _zsh_ai_provider_get_api_key()    - Return API key via REPLY
# _zsh_ai_provider_make_request()   - Make API request, return response via REPLY
# _zsh_ai_provider_parse_response() - Parse response, return commands via REPLY
#
# Optional:
# _zsh_ai_provider_get_models()     - Return available models (for dynamic discovery)
# _zsh_ai_provider_validate_model() - Validate model is supported
EOF
```

**Step 3: Commit**

```bash
git add providers/_provider_interface.zsh
git commit -m "feat: add provider interface documentation"
```

---

## Task 2: Implement OpenAI provider

**Files:**
- Create: `providers/openai.zsh`

**Step 1: Write OpenAI provider**

```zsh
cat > providers/openai.zsh << 'EOF'
#!/bin/zsh
# OpenAI Provider Implementation
typeset -g PROVIDER_NAME="openai"
typeset -g PROVIDER_DISPLAY_NAME="OpenAI"
typeset -g PROVIDER_API_BASE="https://api.openai.com/v1"
typeset -ga PROVIDER_MODELS=("gpt-5-mini" "gpt-5-nano" "o4-mini" "gpt-5.1-codex-mini")
typeset -g PROVIDER_DEFAULT_MODEL="gpt-5-nano"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_OPENAI_API_KEY"
typeset -g PROVIDER_KEY_FILE="openai_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        REPLY="$api_key"
        return 0
    fi

    if [[ -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
        REPLY="$api_key"
        return 0
    fi

    echo "zsh-ai-commands::Error::No OpenAI API key found"
    echo "Please set ZSH_AI_COMMANDS_OPENAI_API_KEY or create ~/.config/zsh-ai-commands/keys/openai_key"
    return 1
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    PROVIDER_API_KEY="$REPLY"

    local response=""
    local http_code=""
    local timeout=30
    local max_retries=2
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/chat/completions" 2>&1)
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
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying..."
                sleep $((2 ** attempt))
                (( attempt++ ))
                continue
            elif [[ "$http_code" =~ ^50[023]$ ]]; then
                echo "zsh-ai-commands::Error::Server error (HTTP $http_code). Retrying..."
                sleep $((2 ** attempt))
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

_zsh_ai_provider_parse_response() {
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
            return 1
        fi
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/openai.zsh
git commit -m "feat: add OpenAI provider module"
```

---

## Task 3: Create provider registry

**Files:**
- Create: `providers/registry.zsh`

**Step 1: Write provider registry**

```zsh
cat > providers/registry.zsh << 'EOF'
#!/bin/zsh
# Provider Registry
# Manages loading and caching of provider modules

typeset -gA _zsh_ai_registry_providers
typeset -g _zsh_ai_registry_current_provider=""

_zsh_ai_registry_load_provider() {
    local provider_name="$1"
    local provider_file="${0:A:h}/providers/${provider_name}.zsh"

    if [[ ! -f "$provider_file" ]]; then
        echo "zsh-ai-commands::Error::Provider not found: $provider_name"
        return 1
    fi

    source "$provider_file"
    _zsh_ai_registry_current_provider="$provider_name"
    return 0
}

_zsh_ai_registry_list_providers() {
    local providers_dir="${0:A:h}/providers"
    local providers=()

    for f in "$providers_dir"/*.zsh(N); do
        local name="${f:t}"
        name="${name%.zsh}"
        if [[ "$name" != "_provider_interface" && "$name" != "registry" ]]; then
            providers+=("$name")
        fi
    done

    echo "${providers[@]}"
}

_zsh_ai_provider_get_model() {
    if [[ -n "$ZSH_AI_COMMANDS_LLM_NAME" ]]; then
        REPLY="$ZSH_AI_COMMANDS_LLM_NAME"
        return 0
    fi
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        local model=$(grep -E "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \n\r')
        if [[ -n "$model" ]]; then
            REPLY="$model"
            return 0
        fi
    fi
    REPLY="$PROVIDER_DEFAULT_MODEL"
}

_zsh_ai_provider_get_models() {
    echo "${PROVIDER_MODELS[@]}"
}

_zsh_ai_provider_validate_model() {
    local model="$1"
    if [[ " ${PROVIDER_MODELS[@]} " == *" $model "* ]]; then
        return 0
    fi
    return 1
}
EOF
```

**Step 2: Commit**

```bash
git add providers/registry.zsh
git commit -m "feat: add provider registry"
```

---

## Task 4: Implement Anthropic provider

**Files:**
- Create: `providers/anthropic.zsh`

**Step 1: Write Anthropic provider**

```zsh
cat > providers/anthropic.zsh << 'EOF'
#!/bin/zsh
# Anthropic Provider Implementation
typeset -g PROVIDER_NAME="anthropic"
typeset -g PROVIDER_DISPLAY_NAME="Anthropic Claude"
typeset -g PROVIDER_API_BASE="https://api.anthropic.com/v1"
typeset -ga PROVIDER_MODELS=(
    "claude-opus-4-6-20250219"
    "claude-sonnet-4-6-20250219"
    "claude-sonnet-4-5-20250929"
    "claude-haiku-4-5-20251015"
)
typeset -g PROVIDER_DEFAULT_MODEL="claude-sonnet-4-6-20250219"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_ANTHROPIC_API_KEY"
typeset -g PROVIDER_KEY_FILE="anthropic_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        REPLY="$api_key"
        return 0
    fi

    if [[ -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
        REPLY="$api_key"
        return 0
    fi

    echo "zsh-ai-commands::Error::No Anthropic API key found"
    echo "Please set ZSH_AI_COMMANDS_ANTHROPIC_API_KEY or create ~/.config/zsh-ai-commands/keys/anthropic_key"
    return 1
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    PROVIDER_API_KEY="$REPLY"
    local max_tokens=1024

    local system_prompt=$(echo "$request_body" | jq -r '.messages[] | select(.role == "system") | .content' 2>/dev/null)
    local user_messages=$(echo "$request_body" | jq '.messages | map(select(.role != "system"))' 2>/dev/null)

    local anthropic_request=$(jq -n \
        --arg model "$model" \
        --argjson max_tokens $max_tokens \
        --argjson messages "$user_messages" \
        --arg system "$system_prompt" \
        '{model: $model, max_tokens: $max_tokens, messages: $messages, system: $system}' 2>/dev/null)

    local response=""
    local http_code=""
    local timeout=30
    local max_retries=2
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${PROVIDER_API_KEY}" \
            -H "anthropic-version: 2023-06-01" \
            -d "$anthropic_request" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/messages" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid Anthropic API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying..."
                sleep $((2 ** attempt))
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::Anthropic API request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
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

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.content[0].text' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::Anthropic API error: $error_msg"
            return 1
        fi
        echo "zsh-ai-commands::Error::Failed to parse Anthropic response"
        return 1
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/anthropic.zsh
git commit -m "feat: add Anthropic provider module"
```

---

## Task 5: Implement Gemini provider

**Files:**
- Create: `providers/gemini.zsh`

**Step 1: Write Gemini provider**

```zsh
cat > providers/gemini.zsh << 'EOF'
#!/bin/zsh
# Google Gemini Provider Implementation
typeset -g PROVIDER_NAME="gemini"
typeset -g PROVIDER_DISPLAY_NAME="Google Gemini"
typeset -g PROVIDER_API_BASE="https://generativelanguage.googleapis.com/v1beta"
typeset -ga PROVIDER_MODELS=("gemini-3-pro" "gemini-3-flash" "gemini-3-flash-thinking" "gemini-2.5-pro" "gemini-2.5-flash")
typeset -g PROVIDER_DEFAULT_MODEL="gemini-3-flash"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_GEMINI_API_KEY"
typeset -g PROVIDER_KEY_FILE="gemini_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        REPLY="$api_key"
        return 0
    fi

    if [[ -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
        REPLY="$api_key"
        return 0
    fi

    echo "zsh-ai-commands::Error::No Gemini API key found"
    echo "Please set ZSH_AI_COMMANDS_GEMINI_API_KEY or create ~/.config/zsh-ai-commands/keys/gemini_key"
    return 1
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    PROVIDER_API_KEY="$REPLY"

    local messages=$(echo "$request_body" | jq '.messages' 2>/dev/null)
    local gemini_request=$(jq -n \
        --argjson contents "$messages" \
        '{contents: $contents, generationConfig: {temperature: 1}}' 2>/dev/null)

    local endpoint="${PROVIDER_API_BASE}/models/${model}:generateContent?keykey=${PROVIDER_API_KEY}"

    local response=""
    local http_code=""
    local timeout=30
    local max_retries=2
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -d "$gemini_request" \
            -w "\n%{http_code}" \
            "$endpoint" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid Gemini API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying..."
                sleep $((2 ** attempt))
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::Gemini API request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
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

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::Gemini API error: $error_msg"
            return 1
        fi
        echo "zsh-ai-commands::Error::Failed to parse Gemini response"
        return 1
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/gemini.zsh
git commit -m "feat: add Gemini provider module"
```

---

## Task 6: Implement Groq provider

**Files:**
- Create: `providers/groq.zsh`

**Step 1: Write Groq provider (OpenAI-compatible)**

```zsh
cat > providers/groq.zsh << 'EOF'
#!/bin/zsh
# Groq Provider Implementation (OpenAI-compatible)
typeset -g PROVIDER_NAME="groq"
typeset -g PROVIDER_DISPLAY_NAME="Groq"
typeset -g PROVIDER_API_BASE="https://api.groq.com/openai/v1"
typeset -ga PROVIDER_MODELS=("llama-3.3-70b-versatile" "llama-3.1-8b-instant" "mixtral-8x7b-32768" "gemma2-9b-it")
typeset -g PROVIDER_DEFAULT_MODEL="llama-3.3-70b-versatile"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_GROQ_API_KEY"
typeset -g PROVIDER_KEY_FILE="groq_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        REPLY="$api_key"
        return 0
    fi

    if [[ -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
        REPLY="$api_key"
        return 0
    fi

    echo "zsh-ai-commands::Error::No Groq API key found"
    echo "Please set ZSH_AI_COMMANDS_GROQ_API_KEY or create ~/.config/zsh-ai-commands/keys/groq_key"
    return 1
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    PROVIDER_API_KEY="$REPLY"

    local response=""
    local http_code=""
    local timeout=30
    local max_retries=2
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/chat/completions" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid Groq API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying..."
                sleep $((2 ** attempt))
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::Groq API request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
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

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.choices[].message.content' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::Groq API error: $error_msg"
            return 1
        fi
        parsed=$(echo "$response" | sed '/"content": "/ s/\\/\\\\/g' | jq -r '.choices[].message.content' 2>/dev/null)
        if [[ -z "$parsed" || "$parsed" == "null" ]]; then
            echo "zsh-ai-commands::Error::Failed to parse Groq response"
            return 1
        fi
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/groq.zsh
git commit -m "feat: add Groq provider module"
```

---

## Task 7: Implement DeepSeek provider

**Files:**
- Create: `providers/deepseek.zsh`

**Step 1: Write DeepSeek provider**

```zsh
cat > providers/deepseek.zsh << 'EOF'
#!/bin/zsh
# DeepSeek Provider Implementation
typeset -g PROVIDER_NAME="deepseek"
typeset -g PROVIDER_DISPLAY_NAME="DeepSeek"
typeset -g PROVIDER_API_BASE="https://api.deepseek.com"
typeset -ga PROVIDER_MODELS=("deepseek-chat" "deepseek-coder" "deepseek-reasoner")
typeset -g PROVIDER_DEFAULT_MODEL="deepseek-chat"
typeset -g PROVIDER_REQUIRES_API_KEY=true
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_DEEPSEEK_API_KEY"
typeset -g PROVIDER_KEY_FILE="deepseek_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
        REPLY="$api_key"
        return 0
    fi

    if [[ -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
        REPLY="$api_key"
        return 0
    fi

    echo "zsh-ai-commands::Error::No DeepSeek API key found"
    echo "Please set ZSH_AI_COMMANDS_DEEPSEEK_API_KEY or create ~/.config/zsh-ai-commands/keys/deepseek_key"
    return 1
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    PROVIDER_API_KEY="$REPLY"

    local response=""
    local http_code=""
    local timeout=30
    local max_retries=2
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${PROVIDER_API_KEY}" \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${PROVIDER_API_BASE}/chat/completions" 2>&1)
        local curl_exit=$?

        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            elif [[ "$http_code" == "401" ]]; then
                echo "zsh-ai-commands::Error::Invalid DeepSeek API key (HTTP 401)"
                return 1
            elif [[ "$http_code" == "429" ]]; then
                echo "zsh-ai-commands::Error::Rate limit exceeded (HTTP 429). Retrying..."
                sleep $((2 ** attempt))
                (( attempt++ ))
                continue
            else
                echo "zsh-ai-commands::Error::DeepSeek API request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            (( attempt++ ))
            if (( attempt <= max_retries )); then
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

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.choices[].message.content' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::DeepSeek API error: $error_msg"
            return 1
        fi
        parsed=$(echo "$response" | sed '/"content": "/ s/\\/\\\\/g' | jq -r '.choices[].message.content' 2>/dev/null)
        if [[ -z "$parsed" || "$parsed" == "null" ]]; then
            echo "zsh-ai-commands::Error::Failed to parse DeepSeek response"
            return 1
        fi
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/deepseek.zsh
git commit -m "feat: add DeepSeek provider module"
```

---

## Task 8: Implement Ollama provider

**Files:**
- Create: `providers/ollama.zsh`

**Step 1: Write Ollama provider**

```zsh
cat > providers/ollama.zsh << 'EOF'
#!/bin/zsh
# Ollama Provider Implementation (Local)
typeset -g PROVIDER_NAME="ollama"
typeset -g PROVIDER_DISPLAY_NAME="Ollama (Local)"
typeset -g PROVIDER_API_BASE="http://localhost:11434"
typeset -ga PROVIDER_MODELS=()
typeset -g PROVIDER_DEFAULT_MODEL=""
typeset -g PROVIDER_REQUIRES_API_KEY=false
typeset -g PROVIDER_KEY_ENV_VAR=""
typeset -g PROVIDER_KEY_FILE=""

_zsh_ai_provider_get_api_key() {
    REPLY=""
    return 0
}

_zsh_ai_provider_get_models() {
    local ollama_host="${ZSH_AI_COMMANDS_OLLAMA_HOST:-$PROVIDER_API_BASE}"
    local models_json=""

    models_json=$(curl -q --max-time 5 "${ollama_host}/api/tags" 2>/dev/null)

    if [[ -n "$models_json" ]]; then
        PROVIDER_MODELS=($(echo "$models_json" | jq -r '.models[].name' 2>/dev/null))
        if [[ ${#PROVIDER_MODELS[@]} -gt 0 ]]; then
            PROVIDER_DEFAULT_MODEL="${PROVIDER_MODELS[1]}"
        fi
    fi

    echo "${PROVIDER_MODELS[@]}"
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"

    local ollama_host="${ZSH_AI_COMMANDS_OLLAMA_HOST:-$PROVIDER_API_BASE}"

    local ollama_request=$(echo "$request_body" | jq --arg model "$model" '. + {model: $model, stream: false}')

    local response=""
    local timeout=60
    local max_retries=1
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            -d "$ollama_request" \
            "${ollama_host}/api/chat" 2>&1)
        local curl_exit=$?

        if (( curl_exit == 0 )); then
            REPLY="$response"
            return 0
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Ollama request timed out after ${timeout}s"
            return 1
        elif (( curl_exit == 7 )); then
            echo "zsh-ai-commands::Error::Cannot connect to Ollama at ${ollama_host}"
            echo "Make sure Ollama is running: ollama serve"
            return 1
        else
            echo "zsh-ai-commands::Error::curl failed with exit code $curl_exit"
            return 1
        fi
    done

    return 1
}

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.message.content' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::Ollama error: $error_msg"
            return 1
        fi
        echo "zsh-ai-commands::Error::Failed to parse Ollama response"
        return 1
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/ollama.zsh
git commit -m "feat: add Ollama provider module"
```

---

## Task 9: Implement OpenAI-compatible provider

**Files:**
- Create: `providers/openai-compatible.zsh`

**Step 1: Write OpenAI-compatible provider**

```zsh
cat > providers/openai-compatible.zsh << 'EOF'
#!/bin/zsh
# OpenAI-Compatible Provider Implementation
# For LM Studio, vLLM, LocalAI, etc.
typeset -g PROVIDER_NAME="openai-compatible"
typeset -g PROVIDER_DISPLAY_NAME="OpenAI Compatible (Local)"
typeset -g PROVIDER_API_BASE="http://localhost:1234/v1"
typeset -ga PROVIDER_MODELS=("local-model")
typeset -g PROVIDER_DEFAULT_MODEL="local-model"
typeset -g PROVIDER_REQUIRES_API_KEY=false
typeset -g PROVIDER_KEY_ENV_VAR="ZSH_AI_COMMANDS_COMPATIBLE_API_KEY"
typeset -g PROVIDER_KEY_FILE="compatible_key"

_zsh_ai_provider_get_api_key() {
    local api_key=""

    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" ]]; then
        api_key=$(head -n1 "$ZSH_AI_COMMANDS_CONFIG_DIR/keys/$PROVIDER_KEY_FILE" 2>/dev/null | tr -d '\n\r')
    fi

    if [[ -z "$api_key" && -n "$PROVIDER_KEY_ENV_VAR" ]]; then
        api_key="${(P)PROVIDER_KEY_ENV_VAR}"
    fi

    REPLY="$api_key"
    return 0
}

_zsh_ai_provider_get_models() {
    local base_url="${ZSH_AI_COMMANDS_COMPATIBLE_BASE:-$PROVIDER_API_BASE}"
    local models_json=""

    models_json=$(curl -q --max-time 5 "${base_url}/models" 2>/dev/null)

    if [[ -n "$models_json" ]]; then
        local models=($(echo "$models_json" | jq -r '.data[].id // .data[]?.id // empty' 2>/dev/null | head -20))
        if [[ ${#models[@]} -gt 0 ]]; then
            PROVIDER_MODELS=("${models[@]}")
            PROVIDER_DEFAULT_MODEL="${models[1]}"
        fi
    fi

    echo "${PROVIDER_MODELS[@]}"
}

_zsh_ai_provider_make_request() {
    local request_body="$1"
    local model
    _zsh_ai_provider_get_model || model="$REPLY"
    _zsh_ai_provider_get_api_key
    local api_key="$REPLY"

    local base_url="${ZSH_AI_COMMANDS_COMPATIBLE_BASE:-$PROVIDER_API_BASE}"
    local auth_header=""

    if [[ -n "$api_key" ]]; then
        auth_header="-H \"Authorization: Bearer ${api_key}\""
    fi

    local response=""
    local timeout=60
    local max_retries=1
    local attempt=0

    while (( attempt <= max_retries )); do
        response=$(curl -q --max-time "$timeout" \
            -H "Content-Type: application/json" \
            $auth_header \
            -d "$request_body" \
            -w "\n%{http_code}" \
            "${base_url}/chat/completions" 2>&1)
        local curl_exit=$?

        local http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')

        if (( curl_exit == 0 )); then
            if [[ "$http_code" == "200" ]]; then
                REPLY="$response"
                return 0
            else
                echo "zsh-ai-commands::Error::Request failed with HTTP $http_code"
                return 1
            fi
        elif (( curl_exit == 7 )); then
            echo "zsh-ai-commands::Error::Cannot connect to ${base_url}"
            return 1
        elif (( curl_exit == 28 )); then
            echo "zsh-ai-commands::Error::Request timed out after ${timeout}s"
            return 1
        else
            echo "zsh-ai-commands::Error::curl failed with exit code $curl_exit"
            return 1
        fi
    done

    return 1
}

_zsh_ai_provider_parse_response() {
    local response="$1"
    local parsed=""

    parsed=$(echo "$response" | jq -r '.choices[].message.content' 2>/dev/null)

    if [[ -z "$parsed" || "$parsed" == "null" ]]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "zsh-ai-commands::Error::API error: $error_msg"
            return 1
        fi
        echo "zsh-ai-commands::Error::Failed to parse response"
        return 1
    fi

    REPLY=$(echo "$parsed" | uniq)
    return 0
}
EOF
```

**Step 2: Commit**

```bash
git add providers/openai-compatible.zsh
git commit -m "feat: add OpenAI-compatible provider module"
```

---

## Task 10: Refactor core to integrate provider registry

**Files:**
- Modify: `zsh-ai-commands.zsh`

**Step 1: Update imports and constants**

Replace lines 1-9 with:

```zsh
#!/bin/zsh

typeset -g ZSH_AI_COMMANDS_CONFIG_DIR="${HOME}/.config/zsh-ai-commands"
typeset -g ZSH_AI_COMMANDS_API_KEY_DIR="${ZSH_AI_COMMANDS_CONFIG_DIR}/keys"
typeset -g ZSH_AI_COMMANDS_CONFIG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/config"
typeset -g ZSH_AI_COMMANDS_LOG_FILE="${ZSH_AI_COMMANDS_CONFIG_DIR}/debug.log"
```

**Step 2: Update initialization function**

Replace `_zsh_ai_commands_init()` with:

```zsh
_zsh_ai_commands_init() {
    _zsh_ai_commands_check_dependencies || return 1
    _zsh_ai_commands_ensure_config_dir || return 1

    # Source provider registry
    source "${0:A:h}/providers/registry.zsh"

    # Determine provider
    local provider="${ZSH_AI_COMMANDS_PROVIDER:-openai}"
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
        local config_provider=$(grep -E "^PROVIDER=" "$ZSH_AI_COMMANDS_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \n\r')
        [[ -n "$config_provider" ]] && provider="$config_provider"
    fi

    # Load provider
    _zsh_ai_registry_load_provider "$provider" || return 1

    # Get API key for current provider
    _zsh_ai_provider_get_api_key || {
        _zsh_ai_registry_get_display_name || true
        echo "zsh-ai-commands::Error::No API key found for $REPLY"
        return 1
    }
    local api_key="$REPLY"
    typeset -g PROVIDER_API_KEY="$api_key"

    # Get model
    _zsh_ai_provider_get_model || ZSH_AI_COMMANDS_LLM_NAME="$REPLY"

    (( ! ${+ZSH_AI_COMMANDS_HOTKEY} )) && typeset -g ZSH_AI_COMMANDS_HOTKEY='^o'
    (( ! ${+ZSH_AI_COMMANDS_LLM_HOTKEY} )) && typeset -g ZSH_AI_COMMANDS_LLM_HOTKEY='^l'
    (( ! ${+ZSH_AI_COMMANDS_N_GENERATIONS} )) && typeset -g ZSH_AI_COMMANDS_N_GENERATIONS=5
    (( ! ${+ZSH_AI_COMMANDS_EXPLAINER} )) && typeset -g ZSH_AI_COMMANDS_EXPLAINER=true
    (( ! ${+ZSH_AI_COMMANDS_HISTORY} )) && typeset -g ZSH_AI_COMMANDS_HISTORY=false

    bindkey "$ZSH_AI_COMMANDS_LLM_HOTKEY" select_llm_model

    return 0
}
```

**Step 3: Update ensure_config_dir to create keys directory**

Replace `_zsh_ai_commands_ensure_config_dir()` with:

```zsh
_zsh_ai_commands_ensure_config_dir() {
    if [[ ! -d "$ZSH_AI_COMMANDS_CONFIG_DIR" ]]; then
        mkdir -p "$ZSH_AI_COMMANDS_CONFIG_DIR" 2>/dev/null || {
            echo "zsh-ai-commands::Error::Could not create config directory"
            return 1
        }
        chmod 700 "$ZSH_AI_COMMANDS_CONFIG_DIR"
    fi

    if [[ ! -d "$ZSH_AI_COMMANDS_API_KEY_DIR" ]]; then
        mkdir -p "$ZSH_AI_COMMANDS_API_KEY_DIR" 2>/dev/null
 chmod 700 "$ZSH_AI_COMMANDS_API_KEY_DIR"
    fi

    # Migration: move old api_key to keys/openai_key
    if [[ -f "$ZSH_AI_COMMANDS_CONFIG_DIR/api_key" && ! -f "$ZSH_AI_COMMANDS_API_KEY_DIR/openai_key" ]]; then
        mv "$ZSH_AI_COMMANDS_CONFIG_DIR/api_key" "$ZSH_AI_COMMANDS_API_KEY_DIR/openai_key"
        chmod 600 "$ZSH_AI_COMMANDS_API_KEY_DIR/openai_key"
    fi

    return 0
}
```

**Step 4: Remove old API key functions and update model selection**

Remove `_zsh_ai_commands_get_api_key()`, `_zsh_ai_commands_setup_curl_config()`, `_zsh_ai_commands_cleanup_curl_config()` functions.

Replace `_zsh_ai_commands_get_llm_model()` with:

```zsh
_zsh_ai_commands_get_llm_model() {
    _zsh_ai_provider_get_model || REPLY="$PROVIDER_DEFAULT_MODEL"
}
```

Replace `_zsh_ai_commands_set_llm_model()` with:

```zsh
_zsh_ai_commands_set_llm_model() {
    _zsh_ai_commands_ensure_config_dir || return 1

    # First, select provider
    local providers=$(_zsh_ai_registry_list_providers)
    local selected_provider=$(echo "$providers" | tr ' ' '\n' | fzf --reverse --height=~50% --prompt="Select Provider: " --header="Choose LLM provider")

    if [[ -z "$selected_provider" ]]; then
        return 1
    fi

    # Load provider
    _zsh_ai_registry_load_provider "$selected_provider" || return 1

    # Get models for provider
    local models=$(_zsh_ai_provider_get_models)
    local selected_model=$(echo "$models" | tr ' ' '\n' | fzf --reverse --height=~50% --prompt="Select Model: " --header="Choose model for $PROVIDER_DISPLAY_NAME")

    if [[ -n "$selected_model" ]]; then
        # Save to config
        if [[ -f "$ZSH_AI_COMMANDS_CONFIG_FILE" ]]; then
            grep -q "^PROVIDER=" "$ZSH_AI_COMMANDS_CONFIG_FILE" && \
                sed -i '' "s/^PROVIDER=.*/PROVIDER=${selected_provider}/" "$ZSH_AI_COMMANDS_CONFIG_FILE" || \
                echo "PROVIDER=${selected_provider}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
            grep -q "^LLM_MODEL=" "$ZSH_AI_COMMANDS_CONFIG_FILE" && \
                sed -i '' "s/^LLM_MODEL=.*/LLM_MODEL=${selected_model}/" "$ZSH_AI_COMMANDS_CONFIG_FILE" || \
                echo "LLM_MODEL=${selected_model}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
        else
            echo "PROVIDER=${selected_provider}" > "$ZSH_AI_COMMANDS_CONFIG_FILE"
            echo "LLM_MODEL=${selected_model}" >> "$ZSH_AI_COMMANDS_CONFIG_FILE"
        fi

        ZSH_AI_COMMANDS_LLM_NAME="$selected_model"
        echo "Provider: $selected_provider, Model: $selected_model"
    fi
}
```

**Step 5: Update fzf_ai_commands to use provider**

In `fzf_ai_commands()`, replace `_zsh_ai_commands_make_request` with `_zsh_ai_provider_make_request` and `_zsh_ai_commands_parse_response` with `_zsh_ai_provider_parse_response`.

Also update the status message:

```zsh
BUFFER="Asking ${PROVIDER_DISPLAY_NAME:-$ZSH_AI_COMMANDS_LLM_NAME} ($ZSH_AI_COMMANDS_LLM_NAME) for a command to do: $user_query. Please wait..."
```

**Step 6: Commit**

```bash
git add zsh-ai-commands.zsh
git commit -m "refactor: integrate provider registry into core"
```

---

## Task 11: Add migration and cleanup

**Files:**
- Modify: `zsh-ai-commands.zsh`

**Step 1: Remove deprecated functions**

Remove these functions:
- `_zsh_ai_commands_setup_curl_config()`
- `_zsh_ai_commands_cleanup_curl_config()`
- `_zsh_ai_commands_cleanup_hook()` (no longer needed)

Remove the global variable `ZSH_AI_COMMANDS_CURL_CONFIG_FILE`.

**Step 2: Commit**

```bash
git add zsh-ai-commands.zsh
git commit -m "refactor: remove deprecated curl config functions"
```

---

## Task 12: Update README documentation

**Files:**
- Modify: `README.md`

**Step 1: Update README with multi-provider documentation**

Replace the Model Selection and Configuration sections with updated content documenting all providers, configuration options, and environment variables.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for multi-provider support"
```

---

## Task 13: Manual testing

**Step 1: Test OpenAI provider**

```bash
# In a new shell
source zsh-ai-commands.zsh
# Type: list all files
# Press Ctrl+O
```

**Step 2: Test provider switching**

```bash
# Press Ctrl+L
# Select different provider
# Select model
# Test command generation
```

**Step 3: Test error handling**

Test with:
- Invalid API key
- Network timeout
- Unsupported model
- Ollama not running

---

## Task 14: Final commit and tag

**Step 1: Create final commit if needed**

```bash
git status
# If changes, commit them
```

**Step 2: Tag release (optional)**

```bash
git tag -a v2.0.0 -m "Multi-provider support"
```
