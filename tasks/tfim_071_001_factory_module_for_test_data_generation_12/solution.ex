  test "build(:post) populates user_id via an inserted user" do
    before_count = length(FakeRepo.all())
    post = Factory.build(:post)

    assert is_integer(post.user_id) and post.user_id > 0
    assert length(FakeRepo.all()) == before_count + 1
  end