  test "fill defaults to nil for empty buckets when the option is omitted" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    :ok = StreamingResampler.push(pid, 0, 5)
    :ok = StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, nil}, {2_000, nil}]
  end