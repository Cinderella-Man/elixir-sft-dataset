  test "build(:post) with a user_id override creates no association record" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())

    post = Factory.build(:post, user_id: existing.id)

    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before
  end