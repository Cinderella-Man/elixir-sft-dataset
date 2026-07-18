  test "build(:post) populates user_id with the id of the user actually inserted" do
    post = Factory.build(:post)
    [newest | _] = FakeRepo.all()
    assert match?(%MyApp.User{}, newest)
    assert is_integer(newest.id)
    assert post.user_id == newest.id
  end