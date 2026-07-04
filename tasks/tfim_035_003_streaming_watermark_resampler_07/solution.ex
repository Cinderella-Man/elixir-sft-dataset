  test "fill :forward carries the last aggregate into empty buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: :forward)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, 5}, {2_000, 5}]
  end