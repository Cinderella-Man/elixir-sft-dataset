defmodule PasswordPolicyEnforcerTest do
  use ExUnit.Case, async: false

  # ExUnit port of the original hand-rolled harness for `PasswordPolicy`.
  #
  # Each original `test(name, ...)` case is mapped 1:1 to an ExUnit `test`, using
  # the same inputs to `PasswordPolicy.validate/2`. Multi-violation `{:error, [..]}`
  # results are compared order-independently (sorted / MapSet) so violation order
  # does not matter, matching the original MapSet.subset?/equal? semantics.
  #
  # Three of the original *expected* values were incorrect (the original harness was
  # never actually invoked, so they were never validated). They are corrected here to
  # the solution's true, spec-conformant behaviour, with the test PURPOSE preserved:
  #   * "common password is case-insensitive" — "PASSWORD1!" has no lowercase and
  #     require_lowercase defaults to true, so :no_lowercase legitimately fires too.
  #   * "too similar to username - distance <= threshold" — Levenshtein("user1234!",
  #     "user") = 5; the original threshold of 3 never triggered rejection. Corrected
  #     to 5 so distance <= threshold actually holds (boundary case).
  #   * "password identical to username is rejected" — "carol" is 5 chars and
  #     min_length defaults to 8, so :too_short legitimately fires alongside similarity.

  defp violations(result) do
    assert {:error, errs} = result
    errs
  end

  # --- Single-rule failures ---

  test "too short" do
    result = PasswordPolicy.validate("Ab1!", %{username: "user", min_length: 8})
    assert Enum.sort(violations(result)) == Enum.sort([:too_short])
  end

  test "too long" do
    result =
      PasswordPolicy.validate("Ab1!" <> String.duplicate("x", 200), %{
        username: "user",
        max_length: 20
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_long])
  end

  test "no uppercase" do
    result = PasswordPolicy.validate("abc123!!", %{username: "user", require_uppercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_uppercase])
  end

  test "no lowercase" do
    result = PasswordPolicy.validate("ABC123!!", %{username: "user", require_lowercase: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_lowercase])
  end

  test "no digit" do
    result = PasswordPolicy.validate("Abcdefg!", %{username: "user", require_digit: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_digit])
  end

  test "no special character" do
    result = PasswordPolicy.validate("Abcdef12", %{username: "user", require_special: true})
    assert Enum.sort(violations(result)) == Enum.sort([:no_special])
  end

  test "common password" do
    result =
      PasswordPolicy.validate("Password1!", %{
        username: "user",
        common_passwords: ["password1!", "letmein"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password])
  end

  test "common password is case-insensitive" do
    # "PASSWORD1!" matches the common list case-insensitively AND has no lowercase
    # letter (require_lowercase defaults to true), so both violations fire.
    result =
      PasswordPolicy.validate("PASSWORD1!", %{
        username: "user",
        common_passwords: ["password1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :no_lowercase])
  end

  test "reused password" do
    result =
      PasswordPolicy.validate("Correct1!", %{
        username: "user",
        previous_passwords: ["OldPass9#", "Correct1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:reused_password])
  end

  test "reuse comparison is exact, so a case variant of a previous password passes" do
    # Reuse rejects only an exact match against :previous_passwords. "COrrect1!" differs
    # from the stored "Correct1!" by letter case alone, so it is not a reuse; it still
    # satisfies every character-class rule and is far from the username.
    case_variant =
      PasswordPolicy.validate("COrrect1!", %{
        username: "user",
        previous_passwords: ["Correct1!"]
      })

    assert case_variant == :ok

    # The exact same string, on the other hand, is a reuse.
    exact =
      PasswordPolicy.validate("Correct1!", %{
        username: "user",
        previous_passwords: ["Correct1!"]
      })

    assert Enum.sort(violations(exact)) == Enum.sort([:reused_password])
  end

  test "one case variant is a common password but not a reused password" do
    # The same stored string sits in both lists: :common_passwords compares
    # case-insensitively (so it matches), while :previous_passwords requires an exact
    # match (so it does not). Only :common_password may fire.
    result =
      PasswordPolicy.validate("Letmein1!", %{
        username: "user",
        common_passwords: ["LETMEIN1!"],
        previous_passwords: ["LETMEIN1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password])
  end

  test "too similar to username - distance <= threshold" do
    # Levenshtein("user1234!", "user") == 5, so the threshold must be >= 5 for the
    # similarity rule to reject (boundary: distance == threshold).
    result =
      PasswordPolicy.validate("user1234!", %{
        username: "user",
        require_uppercase: false,
        max_username_similarity: 5
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_similar_to_username])
  end

  # --- Multiple simultaneous failures ---

  test "multiple violations: too short + no uppercase + no digit" do
    result =
      PasswordPolicy.validate("abc!", %{
        username: "other",
        min_length: 8,
        require_uppercase: true,
        require_digit: true,
        require_lowercase: true,
        require_special: true
      })

    expected = MapSet.new([:too_short, :no_uppercase, :no_digit])
    got = MapSet.new(violations(result))
    assert MapSet.subset?(expected, got)
  end

  test "multiple violations: common + reused" do
    result =
      PasswordPolicy.validate("Letmein1!", %{
        username: "other",
        require_uppercase: false,
        require_digit: false,
        require_special: false,
        require_lowercase: false,
        common_passwords: ["letmein1!"],
        previous_passwords: ["Letmein1!"]
      })

    assert Enum.sort(violations(result)) == Enum.sort([:common_password, :reused_password])
  end

  # --- Passing cases ---

  test "valid password - all rules pass" do
    result =
      PasswordPolicy.validate("Tr0ub4dor&3", %{
        username: "alice",
        min_length: 8,
        max_length: 64,
        require_uppercase: true,
        require_lowercase: true,
        require_digit: true,
        require_special: true,
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert result == :ok
  end

  test "valid password - username similarity just outside threshold" do
    result =
      PasswordPolicy.validate("userXYZW1!", %{
        username: "user",
        require_uppercase: true,
        require_lowercase: false,
        max_username_similarity: 3
      })

    assert result == :ok
  end

  test "valid with no optional rules enabled" do
    result =
      PasswordPolicy.validate("anything", %{
        username: "bob",
        min_length: 1,
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert result == :ok
  end

  # --- Levenshtein edge cases ---

  test "password identical to username is rejected" do
    # "carol" is 5 chars and min_length defaults to 8, so :too_short fires alongside
    # the similarity violation (distance 0 <= 3).
    result =
      PasswordPolicy.validate("carol", %{
        username: "carol",
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false,
        max_username_similarity: 3
      })

    assert Enum.sort(violations(result)) == Enum.sort([:too_short, :too_similar_to_username])
  end

  test "password far from username is accepted" do
    result =
      PasswordPolicy.validate("Zx9#mQpL", %{
        username: "alice",
        max_username_similarity: 3
      })

    assert result == :ok
  end

  test "username similarity uses literal Levenshtein distance without case folding" do
    # Literal distance("ALICE1!x", "alice") == 8 (no character matches, lengths 8 vs 5),
    # which is strictly greater than the default threshold of 3, so the password passes.
    result = PasswordPolicy.validate("ALICE1!x", %{username: "alice"})

    assert result == :ok
  end

  test "max_length defaults to 128 when the option is omitted" do
    too_long = "Aa1!" <> String.duplicate("x", 125)
    assert {:error, errs} = PasswordPolicy.validate(too_long, %{username: "someuser"})
    assert Enum.sort(errs) == Enum.sort([:too_long])

    at_limit = "Aa1!" <> String.duplicate("x", 124)
    assert PasswordPolicy.validate(at_limit, %{username: "someuser"}) == :ok
  end

  test "max_username_similarity defaults to 3 when the option is omitted" do
    # distance("Xyz9!abc", "Xyz9!qrs") == 3, i.e. exactly at the default threshold.
    assert {:error, errs} = PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrs"})
    assert Enum.sort(errs) == Enum.sort([:too_similar_to_username])

    # distance("Xyz9!abc", "Xyz9!qrst") == 4, strictly greater than the default threshold.
    assert PasswordPolicy.validate("Xyz9!abc", %{username: "Xyz9!qrst"}) == :ok
  end

  test "require_uppercase defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("abcdefg1!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_uppercase])
  end

  test "require_digit defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdefg!", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_digit])
  end

  test "require_special defaults to true when the option is omitted" do
    assert {:error, errs} = PasswordPolicy.validate("Abcdef12", %{username: "zzzzzzzz"})
    assert Enum.sort(errs) == Enum.sort([:no_special])
  end
end
