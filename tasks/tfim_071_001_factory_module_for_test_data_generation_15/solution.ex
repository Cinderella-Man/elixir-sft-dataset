  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn ->
          Factory.sequence(:concurrent_seq, fn n -> n end)
        end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end