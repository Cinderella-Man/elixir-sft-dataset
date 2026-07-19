# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule LogRedactorTest do
  use ExUnit.Case, async: false

  setup do
    r = LogRedactor.new([:password, :ssn, :token, :secret, :credit_card])
    %{r: r}
  end

  # -------------------------------------------------------
  # redact/2 — structural masking + keys_masked report
  # -------------------------------------------------------

  test "masks sensitive keys and reports keys_masked", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{username: "alice", password: "s3cr3t"})
    assert scrubbed.username == "alice"
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
  end

  test "masks sensitive keys regardless of value type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert scrubbed.password == "[REDACTED]"
    assert scrubbed.token == "[REDACTED]"
    assert scrubbed.secret == "[REDACTED]"
    assert report.keys_masked == 3
  end

  test "leaves non-sensitive keys untouched", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{user_id: 42, role: "admin"})
    assert scrubbed.user_id == 42
    assert scrubbed.role == "admin"
    assert report.keys_masked == 0
  end

  test "case-insensitive matching for string keys", %{r: r} do
    {scrubbed, report} = LogRedactor.redact(r, %{"Password" => "x", "TOKEN" => "y"})
    assert scrubbed["Password"] == "[REDACTED]"
    assert scrubbed["TOKEN"] == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "recursively counts keys_masked in nested maps", %{r: r} do
    data = %{user: %{name: "carol", creds: %{password: "hunter2", token: "tok"}}}
    {scrubbed, report} = LogRedactor.redact(r, data)
    assert scrubbed.user.name == "carol"
    assert scrubbed.user.creds.password == "[REDACTED]"
    assert scrubbed.user.creds.token == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "counts keys_masked across a list of maps", %{r: r} do
    data = [%{user: "a", password: "1"}, %{user: "b", password: "2"}]
    {scrubbed, report} = LogRedactor.redact(r, data)
    [m1, m2] = scrubbed
    assert m1.password == "[REDACTED]"
    assert m2.password == "[REDACTED]"
    assert report.keys_masked == 2
  end

  test "masks sensitive keys in a keyword list", %{r: r} do
    {scrubbed, report} =
      LogRedactor.redact(r, username: "dave", password: "secret!", role: :viewer)

    assert scrubbed[:username] == "dave"
    assert scrubbed[:password] == "[REDACTED]"
    assert scrubbed[:role] == :viewer
    assert report.keys_masked == 1
  end

  # -------------------------------------------------------
  # redact/2 — pattern scrubbing on string values
  # -------------------------------------------------------

  test "pattern-masks string values under non-sensitive keys and counts them", %{r: r} do
    data = %{message: "ssn 123-45-6789 email a@b.com card 4111-1111-1111-1234"}
    {scrubbed, report} = LogRedactor.redact(r, data)
    refute scrubbed.message =~ "123-45-6789"
    refute scrubbed.message =~ "a@b.com"
    refute scrubbed.message =~ "4111-1111-1111"
    assert scrubbed.message =~ "1234"
    assert report.keys_masked == 0
    assert report.credit_cards == 1
    assert report.emails == 1
    assert report.ssns == 1
  end

  test "sensitive-key values are not additionally pattern-scanned", %{r: r} do
    # password's value looks like an SSN, but is redacted wholesale, not counted as an SSN match
    {scrubbed, report} = LogRedactor.redact(r, %{password: "123-45-6789"})
    assert scrubbed.password == "[REDACTED]"
    assert report.keys_masked == 1
    assert report.ssns == 0
  end

  test "empty map yields an all-zero report", %{r: r} do
    assert LogRedactor.redact(r, %{}) ==
             {%{}, %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}}
  end

  # -------------------------------------------------------
  # redact_string/2
  # -------------------------------------------------------

  test "redact_string masks a dashed credit card and reports one card", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "4111-1111-1111-1234")
    assert scrubbed == "****-****-****-1234"
    assert report.credit_cards == 1
    assert report.keys_masked == 0
  end

  test "redact_string masks an email keeping the first char", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "Contact john.doe@example.com please")
    assert scrubbed =~ "j***@example.com"
    refute scrubbed =~ "john.doe"
    assert report.emails == 1
  end

  test "redact_string masks an SSN", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "SSN: 123-45-6789 on file")
    assert scrubbed =~ "***-**-****"
    assert report.ssns == 1
  end

  test "redact_string counts multiple matches of the same type", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "123-45-6789 and 987-65-4321")
    assert scrubbed == "***-**-**** and ***-**-****"
    assert report.ssns == 2
  end

  test "redact_string on a clean string returns it unchanged with a zero report", %{r: r} do
    {scrubbed, report} = LogRedactor.redact_string(r, "nothing sensitive here")
    assert scrubbed == "nothing sensitive here"
    assert report == %{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
