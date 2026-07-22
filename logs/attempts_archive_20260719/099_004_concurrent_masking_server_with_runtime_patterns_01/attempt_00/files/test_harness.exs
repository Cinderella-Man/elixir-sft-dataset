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
end
