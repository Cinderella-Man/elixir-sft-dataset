  test "raises when the context is missing the username" do
    assert_raise ArgumentError, fn -> PasswordPolicy.audit("whatever", %{min_length: 4}) end
  end