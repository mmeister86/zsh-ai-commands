# ZSH AI Commands

![zsh-ai-commands-demo](./zsh-ai-commands-demo.gif)

This plugin works by asking an LLM for terminal commands that achieve the described target action.

To use it just type what you want to do (e.g. `list all files in this directory`) and hit the configured hotkey (default: `Ctrl+o`).
When the LLM responds with its suggestions just select the one from the list you want to use.

## Supported Providers

zsh-ai-commands supports multiple LLM providers:

| Provider | Type | Default Model | API Key Required |
|----------|------|---------------|------------------|
| OpenAI | Cloud | gpt-5-nano | Yes |
| Anthropic | Cloud | claude-sonnet-4-6-20250219 | Yes |
| Google Gemini | Cloud | gemini-flash-latest | Yes |
| OpenRouter | Cloud | google/gemini-2.5-flash | Yes |
| DeepSeek | Cloud | deepseek-chat | Yes |
| Ollama | Local | (auto-detected) | No |

## Requirements

- [curl](https://curl.se/)
- [fzf](https://github.com/junegunn/fzf)
  - note: you need a recent version of fzf (the apt version for example is fairly old and will not work)
- awk
- [jq](https://jqlang.github.io/jq/)

## Installation

### oh-my-zsh

Clone the repository to your oh-my-zsh custom plugins folder:

```sh
git clone https://github.com/mmeister86/zsh-ai-commands ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-ai-commands
```

Enable it in your `.zshrc` by adding it to your plugin list:

```
plugins=(... zsh-ai-commands ...)
```

## API Key Configuration

API keys can be configured in two ways:

### 1. Config Files (Recommended)

Store your API keys in dedicated files for each provider:

```sh
# Create keys directory
mkdir -p ~/.config/zsh-ai-commands/keys

# OpenAI
echo "sk-xxxxxxxxxxxxxxxxxxxxxxxx" > ~/.config/zsh-ai-commands/keys/openai_key

# Anthropic
echo "sk-ant-xxxxxxxxxxxxxxxxxxxxx" > ~/.config/zsh-ai-commands/keys/anthropic_key

# Google Gemini
echo "AIzaxxxxxxxxxxxxxxxxxxxxxxxx" > ~/.config/zsh-ai-commands/keys/gemini_key

# OpenRouter
echo "sk-or-xxxxxxxxxxxxxxxxxxxxxxx" > ~/.config/zsh-ai-commands/keys/openrouter_key

# DeepSeek
echo "sk-xxxxxxxxxxxxxxxxxxxxxxxx" > ~/.config/zsh-ai-commands/keys/deepseek_key

# Secure the files
chmod 600 ~/.config/zsh-ai-commands/keys/*_key
chmod 700 ~/.config/zsh-ai-commands/keys
```

### 2. Environment Variables

Alternatively, set environment variables in your `.zshrc`:

```sh
# OpenAI
export ZSH_AI_COMMANDS_OPENAI_API_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"

# Anthropic
export ZSH_AI_COMMANDS_ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxxxxxxxxxx"

# Google Gemini
export ZSH_AI_COMMANDS_GEMINI_API_KEY="AIzaxxxxxxxxxxxxxxxxxxxxxxxx"

# OpenRouter
export ZSH_AI_COMMANDS_OPENROUTER_API_KEY="sk-or-xxxxxxxxxxxxxxxxxxxxxxx"

# DeepSeek
export ZSH_AI_COMMANDS_DEEPSEEK_API_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"
```

> **Note:** Be careful not to leak your API keys if sharing your configuration files.

### Local Providers (No API Key Required)

For local providers (Ollama), no API key is needed.

## Model Selection

### Available Models by Provider

#### OpenAI
- `gpt-5-mini`
- `gpt-5-nano` (default)
- `o4-mini`
- `gpt-5.1-codex-mini`

#### Anthropic Claude
- `claude-opus-4-6-20250219`
- `claude-sonnet-4-6-20250219` (default)
- `claude-sonnet-4-5-20250929`
- `claude-haiku-4-5-20251015`

#### Google Gemini
- `gemini-2.5-flash`
- `gemini-2.5-pro`
- `gemini-3.0-flash` (maps to `gemini-3-flash-preview`)
- `gemini-3.0-pro` (maps to `gemini-3-pro-preview`)
- `gemini-flash-latest` (default)
- `gemini-pro-latest`

#### DeepSeek
- `deepseek-chat` (default)
- `deepseek-coder`
- `deepseek-reasoner`

#### Ollama (Local)
Models are automatically discovered from your Ollama installation. Make sure Ollama is running before selecting models.

Common models include:
- `llama3`
- `llama3:8b`
- `mistral`
- `codellama`
- `deepseek-coder`

#### OpenRouter
OpenRouter provides unified access to multiple LLM providers. Popular models include:
- `google/gemini-2.5-flash` (default)
- `anthropic/claude-4.6-sonnet-20260217`
- `deepseek/deepseek-v3.2-20251201`
- `stepfun/step-3.5-flash:free` (free)
- `arcee-ai/trinity-large-preview:free` (free)
- `meta-llama/llama-3.3-70b-instruct`
- `x-ai/grok-4.1-fast`
- `minimax/minimax-m2.5-20260211`

See https://openrouter.ai/models for the full list of available models.

### Default Provider and Model

Configure via config file:

```sh
mkdir -p ~/.config/zsh-ai-commands
echo "PROVIDER=openai" > ~/.config/zsh-ai-commands/config
echo "LLM_MODEL=gpt-5-nano" >> ~/.config/zsh-ai-commands/config
```

Or set environment variables:

```sh
# Note: Provider selection is only available via config file
export ZSH_AI_COMMANDS_LLM_NAME="gpt-5-nano"
```

### Interactive Selection

Press `Ctrl+L` (or your configured `ZSH_AI_COMMANDS_LLM_HOTKEY`) to interactively select a provider and model via fzf before sending the request:

1. First, select your desired provider from the list
2. Then, select the model from the available models for that provider

This is useful for quickly switching between different LLMs without changing your configuration.

## Provider-Specific Configuration

### Ollama

Configure the Ollama host (useful for remote servers):

```sh
export ZSH_AI_COMMANDS_OLLAMA_HOST="http://localhost:11434"
```

Make sure Ollama is running before using this provider:

```sh
ollama serve
```

## Configuration Variables

| Variable                              | Default              | Description                                                                             |
| ------------------------------------- | -------------------- | --------------------------------------------------------------------------------------- |
| `ZSH_AI_COMMANDS_OPENAI_API_KEY`      | (not set)            | OpenAI API key (optional if key file exists)                                            |
| `ZSH_AI_COMMANDS_ANTHROPIC_API_KEY`   | (not set)            | Anthropic API key (optional if key file exists)                                         |
| `ZSH_AI_COMMANDS_GEMINI_API_KEY`      | (not set)            | Google Gemini API key (optional if key file exists)                                     |
| `ZSH_AI_COMMANDS_OPENROUTER_API_KEY`  | (not set)            | OpenRouter API key (optional if key file exists)                                        |
| `ZSH_AI_COMMANDS_DEEPSEEK_API_KEY`    | (not set)            | DeepSeek API key (optional if key file exists)                                          |
| `ZSH_AI_COMMANDS_OLLAMA_HOST`         | `http://localhost:11434` | Ollama server host URL                                                                  |
| `ZSH_AI_COMMANDS_HOTKEY`              | `^o` (Ctrl+o)        | Hotkey to trigger the request                                                           |
| `ZSH_AI_COMMANDS_LLM_HOTKEY`          | `^l` (Ctrl+l)        | Hotkey for interactive provider/model selection                                         |
| `ZSH_AI_COMMANDS_LLM_NAME`            | (provider default)   | LLM model name                                                                          |
| `ZSH_AI_COMMANDS_N_GENERATIONS`       | `5`                  | Number of completions to ask for                                                        |
| `ZSH_AI_COMMANDS_EXPLAINER`           | `true`               | If true, the LLM will comment the command                                               |
| `ZSH_AI_COMMANDS_HISTORY`             | `false`              | If true, save the natural language prompt to the shell history (and atuin if installed) |
| `ZSH_AI_COMMANDS_DEBUG`               | (not set)            | If set to `true`, enables debug logging                                                 |
| `ZSH_AI_COMMANDS_TIMEOUT`             | `30`                 | Request timeout in seconds (60 for local providers)                                     |

## Error Handling

- Configurable timeout for API requests (30s default, 60s for local providers)
- Automatic retry (up to 2 attempts) on network errors and server errors
- Clear error messages for various failure cases
- Debug logging available via `ZSH_AI_COMMANDS_DEBUG=true`

## Known Bugs

- [x] Sometimes the commands in the response have too many / unexpected special characters and the string is not preprocessed enough. In this case the fzf list stays empty.
- [ ] The placeholder message, that should be shown while the request is running, is not always shown. For me it only works if `zsh-autosuggestions` is enabled.
