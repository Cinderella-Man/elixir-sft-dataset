# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule MaskingServerTest do
  use ExUnit.Case, async: false

  setup do
    s = start_supervised!({MaskingServer, [sensitive_keys: [:password, :token, :ssn]]})
    %{s: s}
  end

  # -------------------------------------------------------
  # mask/2 — structural masking
  # -------------------------------------------------------

  test "masks sensitive keys in a flat map", %{s: s} do
    result = MaskingServer.mask(s, %{user: "alice", password: "hunter2"})
    assert result.user == "alice"
    assert result.password == "[MASKED]"
  end

  test "masks sensitive keys regardless of value type", %{s: s} do
    result = MaskingServer.mask(s, %{password: 12345, token: nil})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
  end

  test "recursively masks nested maps", %{s: s} do
    result = MaskingServer.mask(s, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end

  test "masks sensitive keys in a keyword list", %{s: s} do
    result = MaskingServer.mask(s, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end

  test "leaves non-sensitive keys untouched", %{s: s} do
    result = MaskingServer.mask(s, %{count: 7, role: "admin"})
    assert result.count == 7
    assert result.role == "admin"
  end

  test "pattern-masks string values under non-sensitive keys", %{s: s} do
    result = MaskingServer.mask(s, %{note: "email john.doe@example.com"})
    assert result.note =~ "j***@example.com"
    refute result.note =~ "john.doe"
  end

  # -------------------------------------------------------
  # mask_string/2 — built-in patterns
  # -------------------------------------------------------

  test "masks a dashed credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end

  # Single spaces are a documented separator, and separators survive masking.
  test "masks a space-separated credit card keeping the spaces", %{s: s} do
    assert MaskingServer.mask_string(s, "4111 1111 1111 1234") == "**** **** **** 1234"
  end

  # Separators are optional: a bare digit run is still a credit card.
  test "masks an unseparated credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111111234") == "************1234"
  end

  # The documented length range runs from 13 through 19 digits, and only the
  # final four digits ever survive.
  test "masks cards at the shortest and longest documented lengths", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111234") == "*********1234"
    assert MaskingServer.mask_string(s, "1234567890123456789") == "***************6789"
  end

  # Irregular grouping is preserved verbatim while every digit but the last
  # four is starred.
  test "masks a 15-digit card with uneven hyphen groups", %{s: s} do
    assert MaskingServer.mask_string(s, "3782-822463-10005") == "****-******-*0005"
  end

  # Card scrubbing applies to string values reached through mask/2 as well.
  test "masks a space-separated card inside a map value", %{s: s} do
    result = MaskingServer.mask(s, %{note: "card 4111 1111 1111 1234 on file"})
    assert result.note == "card **** **** **** 1234 on file"
  end

  test "masks an SSN", %{s: s} do
    result = MaskingServer.mask_string(s, "SSN: 123-45-6789")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end

  # -------------------------------------------------------
  # add_pattern/3 — runtime custom patterns
  # -------------------------------------------------------

  test "a registered custom pattern is applied during mask_string", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]") == :ok
    assert MaskingServer.mask_string(s, "call 555-1234 now") == "call [PHONE] now"
  end

  test "custom patterns also apply to string values in mask/2", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bSECRET\b/, "[X]")
    result = MaskingServer.mask(s, %{note: "the SECRET code"})
    assert result.note == "the [X] code"
  end

  test "built-in patterns still work after a custom pattern is added", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]")
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end

  # Built-in card masking runs before custom patterns, so a later pattern sees
  # the already-starred card rather than the raw digits.
  test "space-separated cards survive a custom pattern being registered", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bnow\b/, "[WHEN]")
    assert MaskingServer.mask_string(s, "4111 1111 1111 1234 now") == "**** **** **** 1234 [WHEN]"
  end

  # -------------------------------------------------------
  # stats/1
  # -------------------------------------------------------

  test "stats counts keys_masked across mask calls", %{s: s} do
    MaskingServer.mask(s, %{password: "a", token: "b"})
    MaskingServer.mask(s, %{password: "c"})
    assert MaskingServer.stats(s).keys_masked == 3
  end

  test "stats counts patterns_applied across string scrubs", %{s: s} do
    MaskingServer.mask_string(s, "a@b.com and 123-45-6789")
    assert MaskingServer.stats(s).patterns_applied == 2
  end

  # Each card match counts once toward patterns_applied, whatever its
  # separators or length.
  test "stats counts one pattern per card regardless of separator style", %{s: s} do
    MaskingServer.mask_string(s, "4111 1111 1111 1234")
    MaskingServer.mask_string(s, "4111111111234")
    assert MaskingServer.stats(s).patterns_applied == 2
  end

  test "fresh server reports zero stats", %{s: s} do
    assert MaskingServer.stats(s) == %{keys_masked: 0, patterns_applied: 0}
  end

  # -------------------------------------------------------
  # Concurrency
  # -------------------------------------------------------

  test "keys_masked stays exact under concurrent callers", %{s: s} do
    1..50
    |> Enum.map(fn _ ->
      Task.async(fn -> MaskingServer.mask(s, %{password: "x", note: "hi"}) end)
    end)
    |> Enum.each(&Task.await/1)

    assert MaskingServer.stats(s).keys_masked == 50
  end

  test "server started without :sensitive_keys masks no keys at all" do
    d = start_supervised!({MaskingServer, []}, id: :default_opts_server)
    result = MaskingServer.mask(d, %{password: "hunter2", token: "abc"})
    assert result.password == "hunter2"
    assert result.token == "abc"
    assert MaskingServer.stats(d).keys_masked == 0
  end

  test "sensitive key matching is case-insensitive for string and atom keys", %{s: s} do
    result = MaskingServer.mask(s, %{"PASSWORD" => "x", "Token" => "y", User: "z"})
    assert result["PASSWORD"] == "[MASKED]"
    assert result["Token"] == "[MASKED]"
    assert result[:User] == "z"
    assert MaskingServer.stats(s).keys_masked == 2
  end

  test "plain lists of maps and keyword lists are walked element-by-element", %{s: s} do
    result = MaskingServer.mask(s, [%{password: "a", note: "hi"}, [token: "b", user: "eve"]])
    [first, second] = result
    assert first.password == "[MASKED]"
    assert first.note == "hi"
    assert second[:token] == "[MASKED]"
    assert second[:user] == "eve"
  end

  test "custom patterns are applied in registration order", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/alpha/, "beta") == :ok
    assert MaskingServer.add_pattern(s, ~r/beta/, "gamma") == :ok
    assert MaskingServer.mask_string(s, "alpha") == "gamma"
  end

  test "structs under non-sensitive keys are returned unchanged", %{s: s} do
    uri = URI.parse("https://example.com/x?mail=john.doe@example.com")
    result = MaskingServer.mask(s, %{when: ~D[2024-01-01], link: uri, n: 7, flag: :on})
    assert result.when == ~D[2024-01-01]
    assert result.link == uri
    assert result.n == 7
    assert result.flag == :on
    assert MaskingServer.stats(s).patterns_applied == 0
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
