  test "concurrent access yields exactly the integers 1..50 for one sequence" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_range_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert Enum.sort(results) == Enum.to_list(1..50)
  end