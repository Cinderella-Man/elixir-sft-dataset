  test "insert/1 returns {:ok, struct} with an id on success" do
    assert {:ok, user} = Factory.insert(:user)
    assert is_integer(user.id)
  end