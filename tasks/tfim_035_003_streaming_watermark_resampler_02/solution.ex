  test "buckets finalize as the watermark advances (lateness 0)" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    :ok = StreamingResampler.push(pid, 0, 5)
    :ok = StreamingResampler.push(pid, 200, 5)
    # watermark 200 -> bucket [0,1000) not yet closed
    assert StreamingResampler.finalized(pid) == []

    :ok = StreamingResampler.push(pid, 1_500, 10)
    # watermark 1500 -> bucket 0 closes with sum 10
    assert StreamingResampler.finalized(pid) == [{0, 10}]

    :ok = StreamingResampler.push(pid, 2_500, 20)
    # watermark 2500 -> bucket 1000 closes with sum 10
    assert StreamingResampler.finalized(pid) == [{0, 10}, {1_000, 10}]
  end