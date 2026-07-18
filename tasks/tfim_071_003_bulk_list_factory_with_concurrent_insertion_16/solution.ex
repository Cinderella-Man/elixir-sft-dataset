  test "insert(:post) inserts both post and user" do
    before = length(FakeRepo.all())
    post = Factory.insert(:post)
    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) >= before + 2
  end