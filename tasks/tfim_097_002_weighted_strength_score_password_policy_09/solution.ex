  test "raises when the context is missing the username" do
    assert_raise ArgumentError, fn -> PasswordPolicy.evaluate("whatever", %{min_score: 10}) end
  end