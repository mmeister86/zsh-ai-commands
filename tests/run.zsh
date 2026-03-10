#!/bin/zsh

emulate -L zsh
setopt pipefail

typeset -ga TEST_NAMES=()
typeset -ga TEST_FUNCS=()
typeset -gi TEST_TOTAL=0
typeset -gi TEST_PASSED=0
typeset -gi ASSERT_TOTAL=0
typeset -gi ASSERT_FAILED=0
typeset -gi CURRENT_TEST_FAILED=0

test() {
    local name="$1"
    local fn="$2"
    TEST_NAMES+=("$name")
    TEST_FUNCS+=("$fn")
}

_fail_assertion() {
    local message="$1"
    (( ASSERT_TOTAL++ ))
    (( ASSERT_FAILED++ ))
    CURRENT_TEST_FAILED=1
    print -r -- "  FAIL: $message"
    return 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-values differ}"
    (( ASSERT_TOTAL++ ))
    if [[ "$expected" != "$actual" ]]; then
        (( ASSERT_FAILED++ ))
        CURRENT_TEST_FAILED=1
        print -r -- "  FAIL: $message"
        print -r -- "    expected: [$expected]"
        print -r -- "    actual:   [$actual]"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-substring not found}"
    (( ASSERT_TOTAL++ ))
    if [[ "$haystack" != *"$needle"* ]]; then
        (( ASSERT_FAILED++ ))
        CURRENT_TEST_FAILED=1
        print -r -- "  FAIL: $message"
        print -r -- "    needle: [$needle]"
        print -r -- "    actual: [$haystack]"
        return 1
    fi
    return 0
}

assert_status() {
    local expected="$1"
    local actual="$2"
    local message="${3:-unexpected status code}"
    (( ASSERT_TOTAL++ ))
    if [[ "$expected" != "$actual" ]]; then
        (( ASSERT_FAILED++ ))
        CURRENT_TEST_FAILED=1
        print -r -- "  FAIL: $message"
        print -r -- "    expected status: [$expected]"
        print -r -- "    actual status:   [$actual]"
        return 1
    fi
    return 0
}

_run_registered_tests() {
    local i name fn fn_status

    for (( i = 1; i <= ${#TEST_NAMES}; i++ )); do
        name="${TEST_NAMES[i]}"
        fn="${TEST_FUNCS[i]}"
        (( TEST_TOTAL++ ))
        CURRENT_TEST_FAILED=0

        print -r -- "- $name"
        "$fn"
        fn_status=$?

        if (( fn_status == 0 && CURRENT_TEST_FAILED == 0 )); then
            (( TEST_PASSED++ ))
            print -r -- "  PASS"
        else
            if (( fn_status != 0 && CURRENT_TEST_FAILED == 0 )); then
                _fail_assertion "test function returned non-zero without assertion"
            fi
            print -r -- "  FAIL"
        fi
    done
}

main() {
    local test_file test_files=("${PWD}/tests/unit"/*.zsh(N))

    if (( ${#test_files} == 0 )); then
        print -r -- "No tests found under tests/unit"
        return 1
    fi

    for test_file in "${test_files[@]}"; do
        source "$test_file"
    done

    _run_registered_tests

    print -r -- ""
    print -r -- "Summary: ${TEST_PASSED}/${TEST_TOTAL} tests passed, $((ASSERT_TOTAL - ASSERT_FAILED))/${ASSERT_TOTAL} assertions passed"

    if (( ASSERT_FAILED > 0 || TEST_PASSED != TEST_TOTAL )); then
        return 1
    fi

    return 0
}

main "$@"
