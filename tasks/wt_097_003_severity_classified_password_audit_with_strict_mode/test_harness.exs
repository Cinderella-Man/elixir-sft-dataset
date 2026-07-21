defmodule PasswordPolicyV2Test do
  use ExUnit.Case, async: false

  # Exercises the severity-classified audit variant of PasswordPolicy.audit/2,
  # including the :strict promotion of warnings to errors.

  test "weak short password splits into a blocking error and advisory warnings" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})

    assert report == %{
             status: :error,
             errors: [:too_short],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end

  test "warnings alone do not flip the status to error" do
    # "abcdefgh": length 8 (ok), lowercase only. Only advisory violations.
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator"})

    assert report == %{
             status: :ok,
             errors: [],
             warnings: [:no_uppercase, :no_digit, :no_special]
           }
  end

  test "strict mode promotes all warnings into errors and fails the status" do
    report = PasswordPolicy.audit("abcdefgh", %{username: "operator", strict: true})

    assert report == %{
             status: :error,
             errors: [:no_uppercase, :no_digit, :no_special],
             warnings: []
           }
  end

  test "common password is a blocking error" do
    report =
      PasswordPolicy.audit("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert report == %{status: :error, errors: [:common_password], warnings: []}
  end

  test "reused password is a blocking error" do
    report =
      PasswordPolicy.audit("Secret9!x", %{
        username: "operator",
        previous_passwords: ["Secret9!x"]
      })

    assert report == %{status: :error, errors: [:reused_password], warnings: []}
  end

  test "username similarity is a warning, not an error, by default" do
    # Differs from the username by one character -> distance 1 (<= 3), otherwise strong.
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp"})

    assert report == %{status: :ok, errors: [], warnings: [:too_similar_to_username]}
  end

  test "username similarity becomes an error under strict mode" do
    report = PasswordPolicy.audit("Xy9#Kw2$Lm", %{username: "Xy9#Kw2$Lp", strict: true})

    assert report == %{status: :error, errors: [:too_similar_to_username], warnings: []}
  end

  test "a fully valid password produces an empty ok report" do
    report =
      PasswordPolicy.audit("Tr0ub4dor&3", %{
        username: "alice",
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "mixed errors and warnings keep canonical ordering" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})
    assert report.errors == [:too_short]
    assert report.warnings == [:no_uppercase, :no_digit, :no_special]

    strict = PasswordPolicy.audit("abc", %{username: "operator", strict: true})
    assert strict.errors == [:too_short, :no_uppercase, :no_digit, :no_special]
    assert strict.warnings == []
  end

  test "raises when the context is missing the username" do
    assert_raise ArgumentError, fn -> PasswordPolicy.audit("whatever", %{min_length: 4}) end
  end

  test "a lowered :min_length accepts a password shorter than the default" do
    # "Ab1!" is length 4: below the default minimum of 8, but valid once
    # :min_length is overridden to 4, with every character class present.
    report = PasswordPolicy.audit("Ab1!", %{username: "operator", min_length: 4})

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "a password longer than :max_length is a blocking :too_long error" do
    # Length 8 clears the default minimum but exceeds the overridden maximum
    # of 4, so the only violation is the blocking :too_long rule.
    report = PasswordPolicy.audit("Ab1!wxyz", %{username: "operator", max_length: 4})

    assert report == %{status: :error, errors: [:too_long], warnings: []}
  end

  test "a lowered :max_username_similarity suppresses the similarity warning" do
    # Distance from the username is 2; with the threshold overridden to 1 the
    # password is no longer "too similar", so no warning is raised.
    report =
      PasswordPolicy.audit("Xy9#Kw2$Lm", %{
        username: "Xy9#Kw2$Zz",
        max_username_similarity: 1
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "disabling uppercase, digit, and special requirements suppresses their warnings" do
    # Lowercase-only password that would normally warn on the three missing
    # classes; disabling each requirement clears every warning.
    report =
      PasswordPolicy.audit("abcdefgh", %{
        username: "operator",
        require_uppercase: false,
        require_digit: false,
        require_special: false
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "disabling the lowercase requirement suppresses its warning" do
    # Uppercase-only password: with the lowercase, digit, and special
    # requirements disabled, no warning remains.
    report =
      PasswordPolicy.audit("ABCDEFGH", %{
        username: "operator",
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end
end
