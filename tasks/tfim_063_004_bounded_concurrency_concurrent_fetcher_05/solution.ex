  test "sources still queued or running when the timeout fires are reported as :timeout" do
    sources = [
      {:s1, slow_ok(:one, 100)},
      {:s2, slow_ok(:two, 100)},
      {:s3, slow_ok(:three, 100)},
      {:s4, slow_ok(:four, 100)}
    ]

    result = PooledFetcher.fetch_all(sources, 1, 150)

    assert result[:s1] == {:ok, :one}
    assert result[:s2] == {:error, :timeout}
    assert result[:s3] == {:error, :timeout}
    assert result[:s4] == {:error, :timeout}
  end