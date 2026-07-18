  test "grid origin comes from the first pushed point, not from zero" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    :ok = StreamingResampler.push(pid, 1_500, 5)
    :ok = StreamingResampler.push(pid, 3_500, 7)

    # grid starts at bucket 1000; no buckets below it are ever emitted
    assert StreamingResampler.finalized(pid) == [{1_000, 5}, {2_000, nil}]
  end