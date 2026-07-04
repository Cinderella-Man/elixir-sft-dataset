  test "single source" do
    assert PooledFetcher.fetch_all([{:only, slow_ok(:yes, 10)}], 2, 1_000) ==
             %{only: {:ok, :yes}}
  end