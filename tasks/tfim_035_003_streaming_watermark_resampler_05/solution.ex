  test "allowed_lateness keeps a bucket open for late arrivals" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, allowed_lateness: 500)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_200, 10)
    # bucket 0 needs watermark >= 1000 + 500 = 1500 to close; wm is 1200 -> still open
    assert StreamingResampler.finalized(pid) == []

    :ok = StreamingResampler.push(pid, 300, 7)
    assert StreamingResampler.stats(pid).late_dropped == 0

    StreamingResampler.push(pid, 1_800, 3)
    # now wm 1800 >= 1500 -> bucket 0 closes including the late 7
    assert StreamingResampler.finalized(pid) == [{0, 12}]
  end