# Multi-Provider LLM Support Design

**Date:** 2026-03-06
**Status:** Approved

## Overview

Extend zsh-ai-commands to support multiple LLM providers (Anthropic, Google Gemini, Groq, DeepSeek, Ollama) while modernizing the OpenAI model selection.

## Architecture

### Provider Registry Pattern

Each provider is a self-contained module with its own API configuration, authentication, and model list.

```
zsh-ai-commands.zsh          # Main entry point (modified)
providers/
├── _provider_interface.zsh  # Interface definition
├── openai.zsh
├── anthropic.zsh
├── gemini.zsh
├── groq.zsh
├── deepseek.zsh
├── ollama.zsh               # Local models (dynamic discovery)
└── openai-compatible.zsh    # LM Studio, vLLM, etc.
```

### Provider Interface

Each provider implements:

```zsh
typeset -g PROVIDER_NAME="anthropic"
typeset -g PROVIDER_DISPLAY_NAME="Anthropic Claude"
typeset -ga PROVIDER_MODELS=("claude-opus-4-6-20250219" "claude-sonnet-4-6-20250219" ...)
typeset -g PROVIDER_API_BASE="https://api.anthropic.com/v1"
typeset -g PROVIDER_DEFAULT_MODEL="claude-sonnet-4-6-20250219"

_zsh_ai_provider_get_api_key()    # Returns key via REPLY
_zsh_ai_provider_make_request()   # Returns JSON response via REPLY
_zsh_ai_provider_parse_response() # Returns parsed commands via REPLY
```

## Provider API Specifications

| Provider | Auth Header | Endpoint | Request Key | Response Path |
|----------|-------------|----------|-------------|---------------|
| OpenAI | `Authorization: Bearer` | `/v1/chat/completions` | `messages` | `.choices[].message.content` |
| Anthropic | `x-api-key` + `anthropic-version` | `/v1/messages` | `messages` + `max_tokens` (required) | `.content[0].text` |
| Groq | `Authorization: Bearer` | `/openai/v1/chat/completions` | `messages` | `.choices[].message.content` |
| Ollama | None | `/api/chat` | `messages` + `model` | `.message.content` |
| Gemini | `key=` query param | `/v1beta/models/{model}:generateContent` | `contents` + `generationConfig` | `.candidates[].content.parts[].text` |
| DeepSeek | `Authorization: Bearer` | `/chat/completions` | `messages` | `.choices[].message.content` |

## Configuration

### File Structure

```
~/.config/zsh-ai-commands/
├── config                    # Main configuration
├── keys/
│   ├── openai_key
│   ├── anthropic_key
│   ├── gemini_key
│   ├── groq_key
│   └── deepseek_key
└── providers/
    └── custom/               # User-defined providers
```

### Config File Format

```bash
# Provider selection
PROVIDER=openai

# Model selection (provider-specific)
LLM_MODEL=gpt-5-nano

# Provider-specific options
OLLAMA_HOST=http://localhost:11434
OPENAI_COMPATIBLE_BASE=http://localhost:1234/v1
```

## Model Selection

### Supported Models (March 2026)

| Provider | Models | Default |
|----------|--------|---------|
| **OpenAI** | `gpt-5-mini`, `gpt-5-nano`, `o4-mini`, `gpt-5.1-codex-mini` | `gpt-5-nano` |
| **Anthropic** | `claude-opus-4-6-20250219`, `claude-sonnet-4-6-20250219`, `claude-sonnet-4-5-20250929`, `claude-haiku-4-5-20251015` | `claude-sonnet-4-6-20250219` |
| **Gemini** | `gemini-3-pro`, `gemini-3-flash`, `gemini-3-flash-thinking`, `gemini-2.5-pro`, `gemini-2.5-flash` | `gemini-3-flash` |
| **Groq** | `llama-4-8b`, `llama-4-17b`, `llama-4-70b`, `llama-3.3-70b-versatile`, `gemma-3-1b/4b/12b/27b`, `qwen3-32b` | `llama-3.3-70b-versatile` |
| **DeepSeek** | `deepseek-v3.2`, `deepseek-r1`, `deepseek-chat`, `deepseek-coder` | `deepseek-v3.2` |
| **Ollama** | Dynamic via `GET /api/tags` | First available |

### Interactive Selection

`Ctrl+L` opens:
1. Provider selection (fzf)
2. Model selection for chosen provider (fzf)

## Project Structure

```
zsh-ai-commands.plugin.zsh    # Entry point (unchanged)
zsh-ai-commands.zsh           # Core logic (refactored)
providers/
├── _provider_interface.zsh   # Interface documentation
├── openai.zsh
├── anthropic.zsh
├── gemini.zsh
├── groq.zsh
├── deepseek.zsh
├── ollama.zsh
└── openai-compatible.zsh
utils/
└── http.zsh                  # Shared HTTP utilities
```

## Error Handling

| Error | Detection | Response |
|-------|-----------|----------|
| No API key | `_zsh_ai_provider_get_api_key` returns false | Error with setup instructions |
| Invalid API key | HTTP 401 | "Invalid API key" + provider hint |
| Rate limit | HTTP 429 | Retry with exponential backoff (1s, 2s, 4s) |
| Network timeout | curl exit code 28 | Retry up to 2x, then error |
| Provider unreachable | curl exit code 6/7 | "Provider unreachable" + network check |
| Model not found | HTTP 404 | Error + show model list |

### Debug Mode

```zsh
ZSH_AI_COMMANDS_DEBUG=true
ZSH_AI_COMMANDS_LOG_FILE=~/.config/zsh-ai-commands/debug.log
```

## Backward Compatibility & Migration

### Automatic Migration

On first start with new version:
- `~/.config/zsh-ai-commands/api_key` → `~/.config/zsh-ai-commands/keys/openai_key`
- `LLM_MODEL=gpt-4o` in config → `PROVIDER=openai` + `LLM_MODEL=gpt-4o`

### Environment Variables

| Legacy | New | Notes |
|--------|-----|-------|
| `ZSH_AI_COMMANDS_OPENAI_API_KEY` | - | Still supported |
| - | `ZSH_AI_COMMANDS_ANTHROPIC_API_KEY` | New |
| - | `ZSH_AI_COMMANDS_GEMINI_API_KEY` | New |
| - | `ZSH_AI_COMMANDS_GROQ_API_KEY` | New |
| - | `ZSH_AI_COMMANDS_DEEPSEEK_API_KEY` | New |
| `ZSH_AI_COMMANDS_LLM_NAME` | - | Still supported (provider-agnostic) |
| - | `ZSH_AI_COMMANDS_PROVIDER` | New |

### Fallback Behavior

- No provider configured → OpenAI (backward compatibility)
- No API key for selected provider → Error with setup instructions

## Implementation Phases

See implementation plan for detailed steps.
