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

  test "hash digests the raw value, not a pattern-scrubbed rewrite of it" do
    # The strategy sees the original "123-45-6789"; had the SSN pattern been
    # scrubbed to "***-**-****" first, the digest would differ.
    m = FieldMasker.new(%{ssn: :hash})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "123-45-6789"), case: :lower)
    assert result.ssn == expected
  end

  test "hash digests a raw e-mail value rather than its pattern-masked form" do
    m = FieldMasker.new(%{contact: :hash})
    result = FieldMasker.mask(m, %{contact: "john.doe@example.com"})

    expected =
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, "john.doe@example.com"), case: :lower)

    assert result.contact == expected
  end

  test "last4 keeps the raw final four digits of an SSN-shaped value" do
    # Scrubbing first would yield "***-**-****", whose last four characters
    # are stars; the strategy must operate on the untouched value.
    m = FieldMasker.new(%{ssn: :last4})
    result = FieldMasker.mask(m, %{ssn: "123-45-6789"})
    assert result.ssn == "*******6789"
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

  test "hash strategy hashes the inspect representation of a non-string value" do
    m = FieldMasker.new(%{password: :hash})
    result = FieldMasker.mask(m, %{password: :secret})
    expected = "sha256:" <> Base.encode16(:crypto.hash(:sha256, inspect(:secret)), case: :lower)
    assert result.password == expected
  end

  test "mask_string replaces a bare SSN pattern in free text" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "ssn 123-45-6789 ok") == "ssn ***-**-**** ok"
  end

  test "plain lists of maps and keyword lists are walked element-by-element" do
    m = FieldMasker.new(%{password: :redact})
    data = [%{password: "a"}, [password: "b"], "ping x@example.com"]
    result = FieldMasker.mask(m, data)
    assert [%{password: "[MASKED]"}, [password: "[MASKED]"], "ping x***@example.com"] = result
  end

  test "a struct value under a non-policy key is returned unchanged" do
    m = FieldMasker.new(%{password: :redact})
    uri = URI.parse("mailto:john.doe@example.com")
    result = FieldMasker.mask(m, %{contact: uri})
    assert result.contact == uri
  end

  test "a differently-cased string policy key masks an atom data key" do
    m = FieldMasker.new(%{"PassWord" => :redact})
    result = FieldMasker.mask(m, %{password: "x"})
    assert result.password == "[MASKED]"
  end

  test "mask_string masks a bare 13-digit card and a space-separated 19-digit card" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "4111111111234") == "*********1234"
    # 19 digits: only the final four digits (1, 2, 3, 4) survive, separators kept intact.
    assert FieldMasker.mask_string(m, "4111 1111 1111 1111 234") == "**** **** **** ***1 234"
  end
end
