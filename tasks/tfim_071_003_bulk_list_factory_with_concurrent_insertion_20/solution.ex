  test "params_for(:post) user_id matches a user actually persisted in the repo" do
    params = Factory.params_for(:post)
    user = Enum.find(FakeRepo.all(), &(&1.id == params.user_id))
    assert %MyApp.User{} = user
    assert is_binary(user.email)
  end