#!/bin/zsh

source "${PWD}/providers/_common.zsh"

test "_zsh_ai_provider_split_http_response trennt Body und Status" test_split_http_response
test "_zsh_ai_provider_error_message liest type+message" test_error_message_type_and_message
test "_zsh_ai_provider_error_message nutzt message fallback" test_error_message_message_fallback
test "_zsh_ai_provider_parse_openai_text parst String-Content" test_parse_openai_text_string_content
test "_zsh_ai_provider_parse_openai_text parst Array-Content" test_parse_openai_text_array_content
test "_zsh_ai_provider_parse_anthropic_text extrahiert Textblocks" test_parse_anthropic_text

test_split_http_response() {
    local raw_response
    raw_response=$'{"ok":true,"data":"x"}\n200'

    _zsh_ai_provider_split_http_response "$raw_response"
    local rc=$?

    assert_status 0 "$rc" "split_http_response sollte erfolgreich sein"
    assert_eq "200" "$_ZSH_AI_PROVIDER_HTTP_CODE" "HTTP-Status muss übernommen werden"
    assert_eq '{"ok":true,"data":"x"}' "$REPLY" "Response-Body muss ohne Status zurückgegeben werden"
}

test_error_message_type_and_message() {
    local response
    response='{"error":{"type":"invalid_request_error","message":"bad input"}}'

    _zsh_ai_provider_error_message "$response"
    local rc=$?

    assert_status 0 "$rc" "error_message sollte type+message erkennen"
    assert_eq "invalid_request_error: bad input" "$REPLY" "Format für type+message stimmt nicht"
}

test_error_message_message_fallback() {
    local response
    response='{"message":"plain failure"}'

    _zsh_ai_provider_error_message "$response"
    local rc=$?

    assert_status 0 "$rc" "error_message sollte message fallback nutzen"
    assert_eq "plain failure" "$REPLY" "Fallback-Nachricht stimmt nicht"
}

test_parse_openai_text_string_content() {
    local response
    response='{"choices":[{"message":{"content":"ls\npwd"}},{"message":{"content":"ls\npwd"}}]}'

    _zsh_ai_provider_parse_openai_text "$response"
    local rc=$?

    assert_status 0 "$rc" "parse_openai_text sollte String-Content verarbeiten"
    assert_eq $'ls\npwd' "$REPLY" "Duplikate sollten entfernt werden"
}

test_parse_openai_text_array_content() {
    local response
    response='{"choices":[{"message":{"content":[{"type":"output_text","text":"echo "},{"type":"output_text","text":"hello"}]}}]}'

    _zsh_ai_provider_parse_openai_text "$response"
    local rc=$?

    assert_status 0 "$rc" "parse_openai_text sollte Array-Content verarbeiten"
    assert_eq "echo hello" "$REPLY" "Array-Elemente sollten zusammengeführt werden"
}

test_parse_anthropic_text() {
    local response
    response='{"content":[{"type":"text","text":"git status"},{"type":"tool_use","id":"x"},{"type":"text","text":"git status"},{"type":"text","text":"git diff"}]}'

    _zsh_ai_provider_parse_anthropic_text "$response"
    local rc=$?

    assert_status 0 "$rc" "parse_anthropic_text sollte Text-Blocks lesen"
    assert_eq $'git status\ngit diff' "$REPLY" "Anthropic Text sollte gefiltert und dedupliziert sein"
}
