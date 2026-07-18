  test "build(:post) creates the association record and assigns its id" do
    before = length(FakeRepo.all())
    post = Factory.build(:post)

    # The auto-created user is persisted so that its id can be assigned.
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) == before + 1

    assert Enum.any?(FakeRepo.all(), fn
             %MyApp.User{id: id} -> id == post.user_id
             _ -> false
           end)
  end