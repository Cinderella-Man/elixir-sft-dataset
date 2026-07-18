  test "insert(:post) with a user_id override creates only the post row" do
    existing = Factory.insert(:user)
    before = length(FakeRepo.all())
    post = Factory.insert(:post, [:published], user_id: existing.id)
    assert post.user_id == existing.id
    assert post.published == true
    assert length(FakeRepo.all()) == before + 1
  end