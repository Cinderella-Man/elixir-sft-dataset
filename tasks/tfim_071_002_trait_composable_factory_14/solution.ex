  test "user_id override skips the auto-association" do
    existing = Factory.insert(:user)
    before = length(FakeRepo.all())
    post = Factory.build(:post, user_id: existing.id)
    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before
  end