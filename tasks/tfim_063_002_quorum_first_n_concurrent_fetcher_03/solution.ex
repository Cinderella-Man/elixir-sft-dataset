  test "sources that finish with an error do not count toward the quorum" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert result[:err] == {:error, :nope}
    assert result[:win] == {:ok, :yes}
  end