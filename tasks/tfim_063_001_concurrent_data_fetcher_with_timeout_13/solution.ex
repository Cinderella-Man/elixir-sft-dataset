  test "single fast source" do
    result = ConcurrentFetcher.fetch_all([{:only, slow_ok(:yes, 10)}], 500)
    assert %{only: {:ok, :yes}} = result
  end