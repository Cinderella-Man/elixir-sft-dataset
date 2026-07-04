  test "stats reports watermark and open bucket count" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_200, 7)

    stats = StreamingResampler.stats(pid)
    assert stats.watermark == 1_200
    # bucket 0 closed, bucket 1000 open
    assert stats.open_buckets == 1
  end