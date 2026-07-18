  test "build(:post) auto-inserts a user for the association" do
    before = length(FakeRepo.all())
    post = Factory.build(:post)
    assert post.published == false
    assert is_integer(post.user_id) and post.user_id > 0
    assert length(FakeRepo.all()) == before + 1
  end