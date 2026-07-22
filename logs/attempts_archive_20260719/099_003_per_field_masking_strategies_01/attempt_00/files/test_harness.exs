defmodule FieldMaskerTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Strategy: :redact
  # -------------------------------------------------------

  test "redact strategy blanks the value" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{password: "hunter2", user: "alice"})
    assert result.password == "[MASKED]"
    assert result.user == "alice"
  end

  test "redact strategy blanks non-string values too" do
    m = FieldMasker.new(%{token: :redact})
    result = FieldMasker.mask(m, %{token: 12345})
    assert result.token == "[MASKED]"
  end

  # -------------------------------------------------------
  # Strategy: :last4
  # -------------------------------------------------------

  test "last4 keeps the final four characters of a long string" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: "4111111111111234"})
    assert result.card == "************1234"
  end

  test "last4 fully masks a short string" do
    m = FieldMasker.new(%{pin: :last4})
    result = FieldMasker.mask(m, %{pin: "ab"})
    assert result.pin == "**"
  end

  test "last4 leaves an empty string empty" do
    m = FieldMasker.new(%{code: :last4})
    result = FieldMasker.mask(m, %{code: ""})
    assert result.code == ""
  end

  test "last4 on a non-string value falls back to [MASKED]" do
    m = FieldMasker.new(%{card: :last4})
    result = FieldMasker.mask(m, %{card: 42})
    assert result.card == "[MASKED]"
  end

  # -------------------------------------------------------
  # Strategy: :hash
  # -------------------------------------------------------

  test "hash strategy produces a deterministic sha256 hex digest" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: "hunter2"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)
    assert result.password == expected
  end

  test "hash strategy is stable across calls" do
    m = FieldMasker.new(%{password: :hash})
    a = FieldMasker.mask(m, %{password: "same"})
    b = FieldMasker.mask(m, %{password: "same"})
    assert a.password == b.password
  end

  # -------------------------------------------------------
  # Non-policy keys: pattern scrubbing still applies
  # -------------------------------------------------------

  test "string values under non-policy keys get pattern-masked" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{note: "reach me at john.doe@example.com"})
    assert result.note =~ "j***@example.com"
    refute result.note =~ "john.doe"
  end

  test "non-policy non-string values are untouched" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{count: 7, active: true})
    assert result.count == 7
    assert result.active == true
  end

  test "a strategy-transformed value is not additionally pattern-scanned" do
    # value looks like an SSN but :redact wins wholesale
    m = FieldMasker.new(%{ssn: :redact})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "[MASKED]"
  end

  # -------------------------------------------------------
  # Structure / config handling
  # -------------------------------------------------------

  test "different keys can use different strategies" do
    m = FieldMasker.new(%{password: :redact, card: :last4})
    result = FieldMasker.mask(m, %{password: "x", card: "5500005555555559"})
    assert result.password == "[MASKED]"
    assert result.card == "************5559"
  end

  test "recursively applies strategies in nested maps" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end

  test "applies strategies in keyword lists" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, username: "dave", password: "secret!")
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
  end

  test "policy keys match case-insensitively for string keys" do
    m = FieldMasker.new(%{password: :redact})
    result = FieldMasker.mask(m, %{"Password" => "x", "PASSWORD" => "y"})
    assert result["Password"] == "[MASKED]"
    assert result["PASSWORD"] == "[MASKED]"
  end

  test "policies given as a keyword list work the same" do
    m = FieldMasker.new(password: :redact, card: :last4)
    result = FieldMasker.mask(m, %{password: "x", card: "4111111111111234"})
    assert result.password == "[MASKED]"
    assert result.card == "************1234"
  end

  test "mask_string masks a dashed credit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111-1111-1111-1234") == "****-****-****-1234"
  end
end
