#!/bin/zsh

typeset -g _zsh_ai_registry_dir="${PWD}/providers"
source "${PWD}/providers/registry.zsh"

test "_zsh_ai_registry_validate_provider_name akzeptiert gültige Namen" test_validate_provider_name_valid
test "_zsh_ai_registry_validate_provider_name lehnt ungültige Namen ab" test_validate_provider_name_invalid
test "_zsh_ai_registry_list_providers listet nur echte Provider" test_list_providers
test "_zsh_ai_provider_get_default_model liefert OpenAI Default nach Load" test_get_default_model_after_openai_load

test_validate_provider_name_valid() {
    _zsh_ai_registry_validate_provider_name "openai"
    local rc=$?
    assert_status 0 "$rc" "openai sollte als Providername gültig sein"
}

test_validate_provider_name_invalid() {
    _zsh_ai_registry_validate_provider_name "../evil"
    local status_path=$?
    _zsh_ai_registry_validate_provider_name "_hidden"
    local status_prefix=$?

    assert_status 1 "$status_path" "Pfad-Escapes dürfen nicht erlaubt sein"
    assert_status 1 "$status_prefix" "Unterstrich-Präfix muss blockiert werden"
}

test_list_providers() {
    _zsh_ai_registry_list_providers
    local rc=$?
    local providers="$REPLY"

    assert_status 0 "$rc" "list_providers sollte erfolgreich sein"
    assert_contains "$providers" "openai" "openai muss in der Liste enthalten sein"
    assert_contains "$providers" "gemini" "gemini muss in der Liste enthalten sein"
    if [[ "$providers" == *"_common"* || "$providers" == *"registry"* ]]; then
        assert_eq "true" "false" "Interne Dateien dürfen nicht in der Providerliste stehen"
    fi
}

test_get_default_model_after_openai_load() {
    _zsh_ai_registry_load_provider "openai"
    local load_status=$?

    _zsh_ai_provider_get_default_model
    local model_status=$?

    assert_status 0 "$load_status" "openai provider sollte ladbar sein"
    assert_status 0 "$model_status" "default model sollte gelesen werden können"
    assert_eq "gpt-5-nano" "$REPLY" "OpenAI Default-Model stimmt nicht"
}
