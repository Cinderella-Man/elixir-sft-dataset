  test ":last respects timestamp order even for out-of-order arrivals" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :last, allowed_lateness: 1_000)

    StreamingResampler.push(pid, 100, 1)
    StreamingResampler.push(pid, 900, 2)
    StreamingResampler.push(pid, 500, 3)
    StreamingResampler.flush(pid)

    # within bucket 0 the latest timestamp is 900 -> value 2
    assert StreamingResampler.finalized(pid) == [{0, 2}]
  end