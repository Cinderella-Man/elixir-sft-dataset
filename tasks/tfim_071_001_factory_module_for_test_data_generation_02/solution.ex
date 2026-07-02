  test "build/1 returns a struct with default fields" do
    user = Factory.build(:user)
    assert %{name: name, email: email} = user
    assert is_binary(name) and name != ""
    assert is_binary(email) and email != ""
  end