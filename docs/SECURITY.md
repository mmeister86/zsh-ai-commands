# Security Considerations

This document outlines the security model and considerations for zsh-ai-commands.

## Security Overview

zsh-ai-commands is a zsh plugin that generates shell commands using LLM APIs. The security model focuses on:

- **Credential protection**: API keys are stored securely with restricted file permissions
- **Input sanitization**: User queries and LLM output are sanitized before use
- **Safe provider loading**: Provider modules are loaded with path traversal prevention
- **Secure network communication**: All API calls use HTTPS with timeout handling

## API Key Handling

### Storage Options

API keys can be provided in two ways:

1. **File-based (recommended)**: Keys stored in `~/.config/zsh-ai-commands/keys/<provider>_key`
   - Directory permissions: `700` (owner only)
   - File permissions: `600` (owner read/write only)
   - Keys are read with `head -n1` and stripped of newlines

2. **Environment variables**: Set `ZSH_AI_COMMANDS_<PROVIDER>_API_KEY`
   - Example: `ZSH_AI_COMMANDS_OPENAI_API_KEY`, `ZSH_AI_COMMANDS_ANTHROPIC_API_KEY`
   - Environment variables take precedence over file-based keys

### Implementation Details

- Keys directory is created with `chmod 700` during initialization
- Legacy `api_key` files are automatically migrated to the new location with secure permissions
- API keys are never logged or exposed in error messages

### Secure Variable Expansion

The plugin uses zsh's `(P)` flag for dynamic variable expansion instead of `eval`:

```zsh
api_key="${(P)PROVIDER_KEY_ENV_VAR:-}"
```

This prevents code injection that could occur with `eval`-based approaches.

## Input Validation

### User Query Handling

User queries are taken directly from the zsh BUFFER and passed to the LLM via secure JSON building:

```zsh
request_body=$(jq -n \
    --arg model "$ZSH_AI_COMMANDS_LLM_NAME" \
    --arg user "$user_prompt" \
    '{model: $model, messages: [{role: "user", content: $user}]}')
```

Using `jq --arg` and `jq --argjson` ensures proper JSON escaping, preventing JSON injection attacks.

### LLM Output Sanitization

Before displaying LLM-generated commands, output is sanitized via `_zsh_ai_commands_sanitize_command`:

1. **ANSI escape sequences removed**: Prevents terminal escape code injection
2. **Control characters stripped**: Removes `\000-\010`, `\013`, `\014`, `\016-\037`, `\177`
3. **Whitespace trimmed**: Removes leading/trailing whitespace
4. **Single line enforced**: Takes only the first line to prevent multi-line command injection

## Provider Security

### Path Traversal Prevention

Provider loading implements multiple safeguards against path traversal attacks:

1. **Name validation**: Provider names must match `^[a-z0-9_-]+$` regex
   - Prevents `../`, `/`, and special characters
   - Rejects names starting with `_` (internal providers)

2. **Canonical path verification**: After resolving symlinks, the plugin verifies:
   ```zsh
   local canonical_file="${provider_file:A}"
   local canonical_dir="${_zsh_ai_registry_dir:A}"
   if [[ "$canonical_file" != "${canonical_dir}"* ]]; then
       echo "Error::Provider path escapes registry directory"
       return 1
   fi
   ```

This ensures that even symlink attacks cannot load files outside the providers directory.

### Provider Interface

Third-party providers must follow the documented interface in `providers/_provider_interface.zsh`. Internal providers (prefixed with `_`) cannot be loaded directly.

## Network Security

### HTTPS Usage

All provider API calls use HTTPS endpoints:
- OpenAI: `https://api.openai.com/v1/chat/completions`
- Anthropic: `https://api.anthropic.com/v1/messages`
- Gemini: `https://generativelanguage.googleapis.com/v1beta/models/`
- DeepSeek: `https://api.deepseek.com/chat/completions`
- OpenRouter: `https://openrouter.ai/api/v1/chat/completions`

### Timeout Handling

Network requests use `curl` with configurable timeouts. The HTTP response code is captured for error handling via `_zsh_ai_provider_split_http_response`.

### Request Building

All JSON request bodies are built using `jq` with `--arg` and `--argjson` flags to ensure proper escaping of user-provided content.

## Known Security Considerations

### LLM-Generated Commands

**Risk**: LLMs may generate commands that could be harmful if executed without review.

**Mitigations**:
- Commands are displayed via fzf for user review before insertion into the buffer
- Users must explicitly press Enter to execute the selected command
- The `_zsh_ai_commands_sanitize_command` function removes obviously malicious patterns

**Recommendation**: Always review generated commands before execution, especially for:
- Commands involving `rm`, `dd`, `mkfs`, or other destructive operations
- Commands with `sudo` or privilege escalation
- Commands that download and execute remote scripts

### Shell History

If `ZSH_AI_COMMANDS_HISTORY=true`, AI queries are logged to shell history. This may include sensitive information if users paste sensitive data into their queries.

### Local Network Access (Ollama)

The Ollama provider connects to `http://localhost:11434` by default (HTTP, not HTTPS). This is acceptable for local-only access but be aware:
- Traffic is not encrypted
- Only use on trusted networks
- Configure `PROVIDER_API_BASE` for remote Ollama instances with appropriate security

### API Key Exposure

API keys may be visible in:
- Process listings (`ps`) when environment variables are used
- Shell history if exported in `.zshrc` without proper precautions

**Recommendations**:
- Prefer file-based key storage over environment variables
- If using environment variables, set them in a file with restricted permissions and source it
- Never commit API keys to version control

## Reporting Security Issues

If you discover a security vulnerability in zsh-ai-commands, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email security details to the project maintainer
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

We will respond to security reports within 48 hours and work with you to address the issue promptly.

## Security Changelog

| Date | Improvement |
|------|-------------|
| Recent | Provider name validation with regex to prevent path traversal |
| Recent | Canonical path verification for provider file loading |
| Recent | Migration from `eval` to `(P)` flag for variable expansion |
| Recent | Secure JSON building with `jq --arg/--argjson` instead of string interpolation |
| Recent | LLM output sanitization before display (ANSI/control chars, multi-line) |
| Recent | Dedicated keys directory with `700` permissions |
