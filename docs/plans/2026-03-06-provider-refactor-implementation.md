# Provider Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor provider integrations for consistent request/parse/error handling while fixing confirmed provider bugs without changing the CLI UX.

**Architecture:** Introduce shared provider utilities in `providers/_common.zsh` for HTTP execution, error extraction, and robust text parsing. Keep provider-specific request transformation and auth details local to each provider file. Apply targeted bug fixes in init and registry for API-key requirements and model validation.

**Tech Stack:** zsh, curl, jq, fzf, provider-specific HTTP APIs (OpenAI, Anthropic, Gemini, Groq, DeepSeek, Ollama)

---

### Task 1: Add shared provider utility module

**Files:**
- Create: `providers/_common.zsh`
- Modify: `zsh-ai-commands.zsh`

**Step 1: Create failing parser fixture command (manual)**

Run:
```bash
jq -n '{choices:[{message:{content:null,refusal:"policy refusal"}}]}' | jq -r '.choices[].message.content'
```
Expected: `null` (demonstrates current parser fragility in provider files).

**Step 2: Implement common helpers in `providers/_common.zsh`**

Implement functions:
- `_zsh_ai_provider_http_request`
- `_zsh_ai_provider_error_message`
- `_zsh_ai_provider_parse_openai_text`
- `_zsh_ai_provider_parse_anthropic_text`
- `_zsh_ai_provider_parse_gemini_text`
- `_zsh_ai_provider_dedupe_lines`

**Step 3: Source common module from main init path**

In `zsh-ai-commands.zsh`, source `providers/_common.zsh` before provider loading.

**Step 4: Syntax check**

Run:
```bash
zsh -n zsh-ai-commands.zsh providers/_common.zsh
```
Expected: no output.

**Step 5: Commit**

```bash
git add providers/_common.zsh zsh-ai-commands.zsh
git commit -m "refactor: add shared provider request and parse utilities"
```

### Task 2: Fix Anthropic provider correctness and diagnostics

**Files:**
- Modify: `providers/anthropic.zsh`

**Step 1: Write failing reproduction command (manual)**

Run:
```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ZSH_AI_COMMANDS_ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251015","max_tokens":8,"messages":[{"role":"user","content":"ok"}]}' | jq '.error'
```
Expected: `not_found_error`.

**Step 2: Replace invalid model id and keep alias-compatible option**

Update model list/default to valid IDs (`claude-haiku-4-5-20251001` and/or alias `claude-haiku-4-5`).

**Step 3: Migrate request/error/parse paths to common helpers**

- Keep Anthropic payload transformation local.
- Use common error extraction to print provider error type/message on non-200.
- Use common Anthropic parse helper.

**Step 4: Validate with live smoke test**

Run:
```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ZSH_AI_COMMANDS_ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":8,"messages":[{"role":"user","content":"ok"}]}' | jq -r '.content[0].text'
```
Expected: `ok`.

**Step 5: Commit**

```bash
git add providers/anthropic.zsh
git commit -m "fix: correct anthropic model id and improve API diagnostics"
```

### Task 3: Harden OpenAI provider parsing and error handling

**Files:**
- Modify: `providers/openai.zsh`

**Step 1: Add failing parse fixtures (manual)**

Run:
```bash
jq -n '{choices:[{message:{content:null,refusal:"cannot comply"}}]}'
```
Expected: parser should return refusal text instead of generic parse failure after fix.

**Step 2: Refactor provider to common helpers**

- Keep endpoint/auth local.
- Use common OpenAI-compatible parser that handles:
  - string content
  - array-ish fallback
  - refusal fallback when content is null

**Step 3: Improve non-200 error output**

Include API message details from response body.

**Step 4: Live smoke test**

Run:
```bash
curl -sS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $ZSH_AI_COMMANDS_OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5-mini","n":1,"messages":[{"role":"user","content":"docker one-liner"}]}' \
  | jq -r '.choices[0].message.content // .choices[0].message.refusal'
```
Expected: non-empty text output.

**Step 5: Commit**

```bash
git add providers/openai.zsh
git commit -m "fix: make openai response parsing robust for null content cases"
```

### Task 4: Normalize OpenAI-compatible providers via shared parsing

**Files:**
- Modify: `providers/groq.zsh`
- Modify: `providers/deepseek.zsh`
- Modify: `providers/openai-compatible.zsh`

**Step 1: Apply shared request/error parser flow**

Replace duplicated curl/parse blocks with shared helper usage while retaining provider URLs/auth behavior.

**Step 2: DeepSeek model list sanity**

Constrain defaults to documented chat models if required (`deepseek-chat`, `deepseek-reasoner`) while keeping compatibility notes in code.

**Step 3: Verify parse behavior with local fixtures**

Run:
```bash
jq -n '{choices:[{message:{content:"echo hello"}}]}' | jq -r '.choices[].message.content'
```
Expected: parser path remains unchanged for standard OpenAI-compatible responses.

**Step 4: Commit**

```bash
git add providers/groq.zsh providers/deepseek.zsh providers/openai-compatible.zsh
git commit -m "refactor: unify openai-compatible provider error and parse handling"
```

### Task 5: Fix Gemini provider contract mismatch

**Files:**
- Modify: `providers/gemini.zsh`

**Step 1: Reproduce mismatch condition (manual audit)**

Confirm `zsh-ai-commands.zsh` calls provider make_request with one argument and Gemini implementation expects four.

**Step 2: Align signature to core contract**

- Update Gemini `_zsh_ai_provider_make_request()` to single request-body argument.
- Read model and `n` from existing globals/config (same pattern as other providers).

**Step 3: Keep Gemini-specific payload transform local**

Extract prompt from OpenAI-like request and construct `generateContent` payload with valid fields.

**Step 4: Optional live check (if key exists)**

Run:
```bash
print -r -- "gemini_key_set=${ZSH_AI_COMMANDS_GEMINI_API_KEY:+yes}"
```
Expected: `yes` before live endpoint testing.

**Step 5: Commit**

```bash
git add providers/gemini.zsh
git commit -m "fix: align gemini provider request signature with core contract"
```

### Task 6: Respect provider API-key requirements during init

**Files:**
- Modify: `zsh-ai-commands.zsh`

**Step 1: Add failing manual scenario**

Scenario: choose provider with `PROVIDER_REQUIRES_API_KEY=false` and no key configured.
Expected current behavior: init can fail early.

**Step 2: Implement conditional key enforcement**

Only call hard failure path when `PROVIDER_REQUIRES_API_KEY=true`.

**Step 3: Verify with local provider settings**

Run:
```bash
grep -E '^(PROVIDER|LLM_MODEL)=' ~/.config/zsh-ai-commands/config
```
Expected: can initialize with `openai-compatible`/`ollama` without key error.

**Step 4: Commit**

```bash
git add zsh-ai-commands.zsh
git commit -m "fix: enforce api keys only for providers that require them"
```

### Task 7: Remove registry model validation recursion

**Files:**
- Modify: `providers/registry.zsh`

**Step 1: Identify recursion path**

Current `_zsh_ai_provider_validate_model` checks for function with same name and re-calls itself.

**Step 2: Refactor to non-recursive custom hook**

Introduce provider custom hook name (e.g. `_zsh_ai_provider_validate_model_custom`) and call that when present.

**Step 3: Fallback remains array validation**

Keep default check against `PROVIDER_MODELS`.

**Step 4: Syntax + behavior verification**

Run:
```bash
zsh -n providers/registry.zsh
```
Expected: no output.

**Step 5: Commit**

```bash
git add providers/registry.zsh providers/openai-compatible.zsh providers/ollama.zsh
git commit -m "fix: remove recursive provider model validation"
```

### Task 8: End-to-end verification

**Files:**
- Verify only

**Step 1: Run shell syntax checks**

Run:
```bash
zsh -n zsh-ai-commands.zsh providers/*.zsh
```
Expected: no output.

**Step 2: Verify selected config still loads**

Run in a fresh shell:
```bash
source ~/.zshrc
```
Expected: no `zsh-ai-commands::Error` during init.

**Step 3: Manual smoke tests**

- OpenAI path: ask for `docker` and ensure suggestion list appears.
- Anthropic path: switch model to valid Haiku ID/alias and verify response.

**Step 4: Final commit**

```bash
git add .
git commit -m "refactor: stabilize provider stack and diagnostics across vendors"
```
