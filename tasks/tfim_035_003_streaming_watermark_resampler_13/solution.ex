  test "negative timestamps floor toward negative infinity, not toward zero" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    # first point at -500 -> floor(-500/1000) * 1000 = -1000, NOT 0
    :ok = StreamingResampler.push(pid, -500, 1)
    :ok = StreamingResampler.push(pid, 600, 2)
    :ok = StreamingResampler.push(pid, 1_500, 4)

    # watermark 1500 closes bucket -1000 (needs wm >= 0) and bucket 0 (needs wm >= 1000)
    assert StreamingResampler.finalized(pid) == [{-1_000, 1}, {0, 2}]
  end