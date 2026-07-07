defmodule PasswordPolicyV1Test do
  use ExUnit.Case, async: false

  # Exercises the weighted strength-score variant of PasswordPolicy.evaluate/2.
  # Scores are computed by hand from the deterministic formula in the prompt:
  #   length_points = min(len, 20) * 2
  #   class_points  = (# of {upper, lower, digit, special} present) * 10
  #   long_bonus    = if len >= 16, do: 20, else: 0
  #   score         = min(length_points + class_points + long_bonus, 100)

  test "accepts a moderately strong password at the default threshold" do
    # "Tr0ub4dor&3": len 11 -> 22, all 4 classes -> 40, no bonus -> score 62 (>= 60).
    assert PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "alice"}) == {:accepted, 62}
  end

  test "rejects a short weak password with all applicable reasons" do
    # "abc": len 3 -> 6, lowercase only -> 10, score 16. too_short and insufficient_strength.
    assert PasswordPolicy.evaluate("abc", %{username: "operator"}) ==
             {:rejected, 16, [:too_short, :insufficient_strength]}
  end

  test "rejects a common password even when it scores at the threshold" do
    # "Password1!": len 10 -> 20, all 4 classes -> 40, score 60 (meets threshold),
    # but it is on the common list -> case-insensitive rejection.
    result =
      PasswordPolicy.evaluate("Password1!", %{
        username: "operator",
        common_passwords: ["password1!"]
      })

    assert result == {:rejected, 60, [:common_password]}
  end

  test "rejects a strong password that is too similar to the username" do
    # Differs from the username by one character -> Levenshtein distance 1 (<= 3).
    result =
      PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn3", %{username: "Zx9#mQpLwT7$vBn2"})

    assert result == {:rejected, 92, [:too_similar_to_username]}
  end

  test "honors a custom higher min_score" do
    # Score 62 is fine by default but below a custom threshold of 80.
    result = PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "operator", min_score: 80})
    assert result == {:rejected, 62, [:insufficient_strength]}
  end

  test "accepts a long, diverse password and reports the capped-range score" do
    # len 16 -> 32, all 4 classes -> 40, +20 bonus -> score 92.
    assert PasswordPolicy.evaluate("Zx9#mQpLwT7$vBn2", %{username: "operator"}) ==
             {:accepted, 92}
  end

  test "collects multiple rejection reasons in canonical order" do
    # "abc" is short (too_short), on the common list (common_password), and weak
    # (insufficient_strength). Order must be too_short, common_password, insufficient_strength.
    result =
      PasswordPolicy.evaluate("abc", %{username: "operator", common_passwords: ["abc"]})

    assert result == {:rejected, 16, [:too_short, :common_password, :insufficient_strength]}
  end

  test "raises when the context is missing the username" do
    assert_raise ArgumentError, fn -> PasswordPolicy.evaluate("whatever", %{min_score: 10}) end
  end
end
