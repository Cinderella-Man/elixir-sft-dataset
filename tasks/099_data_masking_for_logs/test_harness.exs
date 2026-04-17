defmodule LogMaskerTest do
  use ExUnit.Case, async: true

  setup do
    masker = LogMasker.new([:password, :ssn, :credit_card, :token, :secret])
    %{m: masker}
  end

  # -------------------------------------------------------
  # mask/2 — flat maps
  # -------------------------------------------------------

  test "masks sensitive keys in a flat map", %{m: m} do
    result = LogMasker.mask(m, %{username: "alice", password: "s3cr3t"})
    assert result.username == "alice"
    assert result.password == "[MASKED]"
  end

  test "masks string-keyed sensitive fields", %{m: m} do
    result = LogMasker.mask(m, %{"token" => "abc123", "name" => "Bob"})
    assert result["token"] == "[MASKED]"
    assert result["name"] == "Bob"
  end

  test "leaves non-sensitive keys untouched", %{m: m} do
    data = %{user_id: 42, email: "alice@example.com", role: "admin"}
    result = LogMasker.mask(m, data)
    assert result.user_id == 42
    assert result.role == "admin"
  end

  test "masks sensitive keys whose value is a non-string (integer, nil, list)", %{m: m} do
    result = LogMasker.mask(m, %{password: 12345, token: nil, secret: [1, 2, 3]})
    assert result.password == "[MASKED]"
    assert result.token == "[MASKED]"
    assert result.secret == "[MASKED]"
  end

  # -------------------------------------------------------
  # mask/2 — nested maps
  # -------------------------------------------------------

  test "recursively masks nested maps", %{m: m} do
    data = %{
      user: %{
        name: "carol",
        credentials: %{password: "hunter2", token: "tok_xyz"}
      }
    }

    result = LogMasker.mask(m, data)
    assert result.user.name == "carol"
    assert result.user.credentials.password == "[MASKED]"
    assert result.user.credentials.token == "[MASKED]"
  end

  test "handles deeply nested structures", %{m: m} do
    data = %{a: %{b: %{c: %{password: "deep"}}}}
    result = LogMasker.mask(m, data)
    assert result.a.b.c.password == "[MASKED]"
  end

  # -------------------------------------------------------
  # mask/2 — lists of maps
  # -------------------------------------------------------

  test "masks sensitive keys in a list of maps", %{m: m} do
    data = [
      %{user: "alice", password: "pass1"},
      %{user: "bob", password: "pass2"}
    ]

    [r1, r2] = LogMasker.mask(m, data)
    assert r1.user == "alice"
    assert r1.password == "[MASKED]"
    assert r2.user == "bob"
    assert r2.password == "[MASKED]"
  end

  test "handles mixed maps containing lists of maps", %{m: m} do
    data = %{
      page: 1,
      results: [
        %{name: "Alice", credit_card: "4111111111111234"},
        %{name: "Bob", credit_card: "5500005555555559"}
      ]
    }

    result = LogMasker.mask(m, data)
    assert result.page == 1
    [r1, r2] = result.results
    assert r1.name == "Alice"
    assert r1.credit_card == "[MASKED]"
    assert r2.name == "Bob"
    assert r2.credit_card == "[MASKED]"
  end

  # -------------------------------------------------------
  # mask/2 — keyword lists
  # -------------------------------------------------------

  test "masks sensitive keys in a keyword list", %{m: m} do
    data = [username: "dave", password: "secret!", role: :viewer]
    result = LogMasker.mask(m, data)
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
    assert result[:role] == :viewer
  end

  # -------------------------------------------------------
  # mask/2 — string values get pattern-masked even on safe keys
  # -------------------------------------------------------

  test "applies pattern masking to string values on non-sensitive keys", %{m: m} do
    data = %{message: "User ssn is 123-45-6789, email: foo@bar.com"}
    result = LogMasker.mask(m, data)
    refute result.message =~ "123-45-6789"
    refute result.message =~ "foo@bar.com"
  end

  # -------------------------------------------------------
  # mask_string/2 — credit card patterns
  # -------------------------------------------------------

  test "masks credit card number (no separators)", %{m: m} do
    result = LogMasker.mask_string(m, "card: 4111111111111234 end")
    refute result =~ "411111111111"
    assert result =~ "1234"
  end

  test "masks credit card number with dashes", %{m: m} do
    result = LogMasker.mask_string(m, "4111-1111-1111-1234")
    assert result == "****-****-****-1234"
  end

  test "masks credit card number with spaces", %{m: m} do
    result = LogMasker.mask_string(m, "4111 1111 1111 1234")
    assert result == "**** **** **** 1234"
  end

  test "last 4 digits of credit card are preserved", %{m: m} do
    result = LogMasker.mask_string(m, "5500005555555559")
    assert String.ends_with?(result, "5559")
    refute result =~ "550000"
  end

  # -------------------------------------------------------
  # mask_string/2 — email patterns
  # -------------------------------------------------------

  test "masks email local part keeping first char", %{m: m} do
    result = LogMasker.mask_string(m, "Contact john.doe@example.com please")
    assert result =~ "j***@example.com"
    refute result =~ "john.doe"
  end

  test "masks multiple emails in one string", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com and carol@domain.org")
    assert result =~ "a***@b.com"
    assert result =~ "c***@domain.org"
  end

  test "single-char local part email is handled without crashing", %{m: m} do
    result = LogMasker.mask_string(m, "a@b.com")
    assert result =~ "@b.com"
  end

  # -------------------------------------------------------
  # mask_string/2 — SSN patterns
  # -------------------------------------------------------

  test "masks SSN pattern", %{m: m} do
    result = LogMasker.mask_string(m, "SSN: 123-45-6789 on file")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end

  test "masks multiple SSNs in one string", %{m: m} do
    result = LogMasker.mask_string(m, "123-45-6789 and 987-65-4321")
    assert result == "***-**-**** and ***-**-****"
  end

  # -------------------------------------------------------
  # mask_string/2 — combined patterns
  # -------------------------------------------------------

  test "masks multiple pattern types in one string", %{m: m} do
    input = "email: user@test.com, ssn: 000-11-2222, card: 4111-1111-1111-9999"
    result = LogMasker.mask_string(m, input)
    refute result =~ "user@test.com"
    refute result =~ "000-11-2222"
    refute result =~ "4111-1111-1111"
    assert result =~ "9999"
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty map returns empty map", %{m: m} do
    assert LogMasker.mask(m, %{}) == %{}
  end

  test "empty string returns empty string", %{m: m} do
    assert LogMasker.mask_string(m, "") == ""
  end

  test "string with no sensitive patterns is returned unchanged", %{m: m} do
    plain = "Hello, world! Nothing sensitive here."
    assert LogMasker.mask_string(m, plain) == plain
  end

  test "masker with empty sensitive_keys list masks nothing structurally", %{m: _} do
    empty_masker = LogMasker.new([])
    data = %{password: "visible", token: "also_visible"}
    result = LogMasker.mask(empty_masker, data)
    # Structural keys not masked, but string patterns still apply
    # password value is not a pattern-matched string so it passes through
    assert result.password == "visible"
    assert result.token == "also_visible"
  end

  test "case-insensitive key matching for string keys", %{m: m} do
    result = LogMasker.mask(m, %{"Password" => "secret", "TOKEN" => "abc"})
    assert result["Password"] == "[MASKED]"
    assert result["TOKEN"] == "[MASKED]"
  end
end
