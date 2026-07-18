  test "insert(:post, user_id: id) respects user_id override and skips auto-association" do
    existing_user = Factory.insert(:user)
    before_count = length(FakeRepo.all())

    post = Factory.insert(:post, user_id: existing_user.id)
    assert post.user_id == existing_user.id
    assert length(FakeRepo.all()) == before_count + 1
  end