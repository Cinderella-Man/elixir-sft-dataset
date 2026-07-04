  test "insert(:post) success inserts both user and post" do
    before = length(FakeRepo.all())
    assert {:ok, post} = Factory.insert(:post)
    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) == before + 2
  end