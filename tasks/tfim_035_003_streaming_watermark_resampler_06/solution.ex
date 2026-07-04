  test "empty buckets in the middle are emitted contiguously (fill :nil)" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: :nil)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, nil}, {2_000, nil}]
  end