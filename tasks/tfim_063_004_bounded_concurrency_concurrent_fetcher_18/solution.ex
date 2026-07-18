  test "concurrent callers each get an independent result map" do
    runners =
      for i <- 1..4 do
        Task.async(fn ->
          PooledFetcher.fetch_all([{{:src, i}, fn -> {:ok, i} end}], 2, 2_000)
        end)
      end

    assert Task.await_many(runners, 5_000) == for(i <- 1..4, do: %{{:src, i} => {:ok, i}})

    assert PooledFetcher.fetch_all([{:later, fn -> {:ok, :fresh} end}], 1, 2_000) ==
             %{later: {:ok, :fresh}}
  end