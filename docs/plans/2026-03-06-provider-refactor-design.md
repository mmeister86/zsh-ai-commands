# Provider Refactor Design (Compatible)

## Goal

Refactor the provider layer for maintainability and robustness while preserving existing user-visible behavior, except for confirmed bug fixes.

## Scope

- Keep current provider architecture and command UX intact.
- Centralize duplicated request/error/parse logic.
- Fix confirmed correctness bugs:
  - Invalid Anthropic model snapshot in provider list/default path.
  - Fragile OpenAI parsing when `content` is null or differently structured.
  - Gemini provider function signature mismatch vs core call contract.
  - Init path not respecting `PROVIDER_REQUIRES_API_KEY=false`.
  - Recursive model validation logic in registry.

## Non-Goals

- No migration from Chat Completions to Responses API.
- No provider feature expansion (tools, streaming, new prompt schema).
- No CLI interaction flow changes.

## Design

### 1) Shared provider utilities

Introduce `providers/_common.zsh` with generic helpers used by all remote providers:

- `_zsh_ai_provider_http_json_request`
  - Executes curl call with configurable URL, headers, timeout, body.
  - Returns body and status code separately via `REPLY` and an output variable.
  - Normalizes network errors and timeout diagnostics.

- `_zsh_ai_provider_extract_error`
  - Parses common error fields (e.g. `.error.type`, `.error.message`, fallback text).
  - Returns a compact user-facing diagnostic string.

- `_zsh_ai_provider_parse_text_candidates`
  - Robust extraction from known response shapes:
    - OpenAI-compatible: `.choices[].message.content` (string/array fallback)
    - Anthropic: `.content[].text`
    - Gemini: `.candidates[].content.parts[].text`
    - Fallback refusal fields when content is null.
  - Deduplicates and returns newline-separated options.

### 2) Provider file responsibilities

Provider files stay responsible for:

- model catalog/defaults
- auth header/query-key specifics
- endpoint path
- request transformation into provider-native payload

Provider files delegate request execution and generic parsing/error handling to `_common.zsh`.

### 3) Compatibility and bug-fix corrections

- Anthropic models:
  - Replace invalid `claude-haiku-4-5-20251015` with valid snapshot and/or alias.
- OpenAI parser:
  - Handle nullable content and refusal paths without generic parse failure.
- Gemini signature:
  - Align `_zsh_ai_provider_make_request` to the core single-argument call contract.
- API key requirement:
  - In init, only enforce key presence when `PROVIDER_REQUIRES_API_KEY=true`.
- Registry validation:
  - Remove recursive self-call pattern by splitting custom validator naming.

### 4) Diagnostics strategy

- On non-200 responses, include vendor error message whenever available.
- Keep concise user-facing errors while enabling richer debug details when `ZSH_AI_COMMANDS_DEBUG=true`.

### 5) Verification strategy

- Static checks:
  - `zsh -n` over updated provider files.
- Functional checks:
  - Minimal live checks for OpenAI and Anthropic (already reproducible from user).
  - Sanity parse checks for representative JSON payloads.

## Risks and Mitigations

- Risk: changing shared code affects all providers.
  - Mitigation: keep transformation logic provider-local; centralize only stable primitives.
- Risk: parser over-generalization drops provider-specific edge cases.
  - Mitigation: keep provider-specific parse fallback hooks where needed.

## Rollout

1. Add `_common.zsh`.
2. Migrate OpenAI + Anthropic first (currently failing paths).
3. Migrate Gemini/Groq/DeepSeek/OpenAI-compatible/Ollama.
4. Fix init + registry compatibility issues.
5. Run validation commands and manual smoke checks.
