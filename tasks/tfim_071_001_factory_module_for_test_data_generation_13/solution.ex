  test "insert(:post) inserts both the post and its user" do
    before_count = length(FakeRepo.all())
    post = Factory.insert(:post)

    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) >= before_count + 2
  end