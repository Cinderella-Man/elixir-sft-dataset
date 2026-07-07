  test "collects multiple rejection reasons in canonical order" do
    # "abc" is short (too_short), on the common list (common_password), and weak
    # (insufficient_strength). Order must be too_short, common_password, insufficient_strength.
    result =
      PasswordPolicy.evaluate("abc", %{username: "operator", common_passwords: ["abc"]})

    assert result == {:rejected, 16, [:too_short, :common_password, :insufficient_strength]}
  end