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

  test "default max_length of 128 allows 128 chars and blocks 129 with :too_long" do
    at_limit = String.duplicate("Aa1!", 32)
    assert String.length(at_limit) == 128

    assert PasswordPolicy.audit(at_limit, %{username: "operator"}) ==
             %{status: :ok, errors: [], warnings: []}

    over_limit = at_limit <> "z"

    assert PasswordPolicy.audit(over_limit, %{username: "operator"}) ==
             %{status: :error, errors: [:too_long], warnings: []}
  end

  test "similarity warning fires at a distance exactly equal to the default threshold" do
    # "operat0r!2" vs "operator": substitute o->0, insert "!", insert "2" => distance 3.
    assert PasswordPolicy.audit("Operat0r!2", %{username: "operator"}) ==
             %{status: :ok, errors: [], warnings: [:too_similar_to_username]}

    # One more insertion => distance 4, above the default threshold of 3.
    assert PasswordPolicy.audit("Operat0r!23", %{username: "operator"}) ==
             %{status: :ok, errors: [], warnings: []}
  end

  test "previous password reuse is compared exactly, so case differences are not reuse" do
    report =
      PasswordPolicy.audit("Secret9!x", %{
        username: "operator",
        previous_passwords: ["secret9!X"]
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "character-class requirements can each be disabled via context flags" do
    report =
      PasswordPolicy.audit("@@@@@@@@", %{
        username: "operator",
        require_uppercase: false,
        require_lowercase: false,
        require_digit: false,
        require_special: false
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end

  test "custom min_length blocks below the limit and accepts exactly the limit" do
    ctx = %{username: "operator", min_length: 12}

    assert PasswordPolicy.audit("Ab1!Ab1!", ctx) ==
             %{status: :error, errors: [:too_short], warnings: []}

    assert PasswordPolicy.audit("Ab1!Ab1!Ab1!", ctx) ==
             %{status: :ok, errors: [], warnings: []}
  end

  test "missing lowercase alone is reported as the :no_lowercase warning" do
    assert PasswordPolicy.audit("ABCDEFG1!", %{username: "operator"}) ==
             %{status: :ok, errors: [], warnings: [:no_lowercase]}
  end
end
