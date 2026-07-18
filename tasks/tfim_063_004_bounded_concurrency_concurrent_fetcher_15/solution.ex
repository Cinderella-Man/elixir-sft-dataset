  test "duplicate names collapse to the last recorded value and shrink the map" do
    sources = [
      {:dup, fn -> {:ok, :first} end},
      {:dup, fn -> {:ok, :second} end},
      {:other, fn -> {:ok, :o} end}
    ]

    result = PooledFetcher.fetch_all(sources, 1, 2_000)

    assert result == %{dup: {:ok, :second}, other: {:ok, :o}}
    assert map_size(result) == 2
  end