  test "late points into an already-finalized bucket are dropped and counted" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_500, 10)
    # bucket 0 is now finalized (next awaiting emission is 1000)
    assert StreamingResampler.finalized(pid) == [{0, 5}]

    :ok = StreamingResampler.push(pid, 300, 99)
    assert StreamingResampler.finalized(pid) == [{0, 5}]
    assert StreamingResampler.stats(pid).late_dropped == 1
  end