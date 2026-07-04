  test "flush finalizes the remaining open buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    Enum.each([{0, 5}, {200, 5}, {1_500, 10}, {2_500, 20}], fn {t, v} ->
      StreamingResampler.push(pid, t, v)
    end)

    assert StreamingResampler.flush(pid) == [{0, 10}, {1_000, 10}, {2_000, 20}]
  end