  test "points after flush that map to emitted buckets are late drops" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 900, 5)
    StreamingResampler.flush(pid)

    :ok = StreamingResampler.push(pid, 100, 99)
    assert StreamingResampler.stats(pid).late_dropped == 1
    assert StreamingResampler.finalized(pid) == [{0, 10}]
  end