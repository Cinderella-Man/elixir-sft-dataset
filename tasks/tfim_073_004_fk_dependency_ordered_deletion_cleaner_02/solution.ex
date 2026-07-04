  test "start/2 issues no SQL" do
    assert {:ok, :deletion} =
             DBCleaner.start(:deletion,
               repo: FakeRepo,
               tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
             )

    assert FakeRepo.calls() == []
  end