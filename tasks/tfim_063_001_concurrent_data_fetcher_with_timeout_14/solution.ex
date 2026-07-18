  test "single timed-out source" do
    result = ConcurrentFetcher.fetch_all([{:only, slow_ok(:yes, 500)}], 50)
    assert %{only: {:error, :timeout}} = result
  end