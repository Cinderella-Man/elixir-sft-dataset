  test "build_list/2 returns the requested count" do
    users = Factory.build_list(4, :user)
    assert length(users) == 4
  end