  test "first/mean/count/max/min aggregations over an out-of-order bucket" do
    {:ok, first} = StreamingResampler.start_link(1_000, agg: :first, allowed_lateness: 1_000)
    :ok = StreamingResampler.push(first, 900, 2)
    :ok = StreamingResampler.push(first, 100, 1)
    assert StreamingResampler.flush(first) == [{0, 1}]

    {:ok, mean} = StreamingResampler.start_link(1_000, agg: :mean)
    :ok = StreamingResampler.push(mean, 0, 1)
    :ok = StreamingResampler.push(mean, 500, 2)
    assert StreamingResampler.flush(mean) == [{0, 1.5}]

    {:ok, count} = StreamingResampler.start_link(1_000, agg: :count)
    :ok = StreamingResampler.push(count, 0, 7)
    :ok = StreamingResampler.push(count, 500, 7)
    [{0, count_value}] = StreamingResampler.flush(count)
    assert count_value === 2

    {:ok, max} = StreamingResampler.start_link(1_000, agg: :max)
    {:ok, min} = StreamingResampler.start_link(1_000, agg: :min)

    Enum.each([{0, 3}, {400, 9}, {800, 5}], fn {t, v} ->
      :ok = StreamingResampler.push(max, t, v)
      :ok = StreamingResampler.push(min, t, v)
    end)

    assert StreamingResampler.flush(max) == [{0, 9}]
    assert StreamingResampler.flush(min) == [{0, 3}]
  end