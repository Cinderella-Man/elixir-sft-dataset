  test "a blocked fetch does not stop sibling results from being collected" do
    blocker = fn ->
      Process.sleep(10_000)
      {:ok, :never}
    end

    sources = [
      {:blocker, blocker},
      {:fast1, fn -> {:ok, 1} end},
      {:fast2, fn -> {:ok, 2} end}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 300)

    assert result[:fast1] == {:ok, 1}
    assert result[:fast2] == {:ok, 2}
    assert result[:blocker] == {:error, :timeout}
  end