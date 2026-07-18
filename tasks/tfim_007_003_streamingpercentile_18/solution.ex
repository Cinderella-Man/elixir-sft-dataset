  test "start_link registers the process under the :name option" do
    {:ok, pid} = StreamingPercentile.start_link(name: :streaming_percentile_named)
    assert :ok = StreamingPercentile.push(:streaming_percentile_named, "a", 42, 3)
    assert {:ok, [42.0]} = StreamingPercentile.window(:streaming_percentile_named, "a")
    assert Process.alive?(pid)
  end