  test "timeout_ms 0 times out every source, even instantly-returning ones" do
    sources = for i <- 1..8, do: {i, fn -> {:ok, i} end}

    result = PooledFetcher.fetch_all(sources, 8, 0)

    assert map_size(result) == 8

    for i <- 1..8 do
      assert result[i] == {:error, :timeout},
             "source #{i} was collected despite an already-spent budget: #{inspect(result[i])}"
    end
  end