  test "honors a custom higher min_score" do
    # Score 62 is fine by default but below a custom threshold of 80.
    result = PasswordPolicy.evaluate("Tr0ub4dor&3", %{username: "operator", min_score: 80})
    assert result == {:rejected, 62, [:insufficient_strength]}
  end