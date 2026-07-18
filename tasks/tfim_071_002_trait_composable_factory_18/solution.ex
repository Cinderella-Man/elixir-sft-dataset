  test "insert/1 persists a post row plus its association row" do
    before = length(FakeRepo.all())
    post = Factory.insert(:post)
    assert is_integer(post.id)
    records = FakeRepo.all()
    assert length(records) == before + 2

    assert Enum.any?(records, fn r ->
             match?(%MyApp.Post{}, r) and r.id == post.id
           end)
  end