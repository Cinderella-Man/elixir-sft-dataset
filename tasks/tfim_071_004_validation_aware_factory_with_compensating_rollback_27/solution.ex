  test "insert(:post) with a user_id override inserts only the post record" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())
    assert {:ok, post} = Factory.insert(:post, user_id: existing.id)
    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before + 1
  end