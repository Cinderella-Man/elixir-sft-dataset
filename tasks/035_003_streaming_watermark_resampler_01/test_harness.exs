defmodule StreamingResamplerTest do
  use ExUnit.Case, async: false

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

  test "flush finalizes the remaining open buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    Enum.each([{0, 5}, {200, 5}, {1_500, 10}, {2_500, 20}], fn {t, v} ->
      StreamingResampler.push(pid, t, v)
    end)

    assert StreamingResampler.flush(pid) == [{0, 10}, {1_000, 10}, {2_000, 20}]
  end

  test "late points into an already-finalized bucket are dropped and counted" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_500, 10)
    # bucket 0 is now finalized (next awaiting emission is 1000)
    assert StreamingResampler.finalized(pid) == [{0, 5}]

    :ok = StreamingResampler.push(pid, 300, 99)
    assert StreamingResampler.finalized(pid) == [{0, 5}]
    assert StreamingResampler.stats(pid).late_dropped == 1
  end

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

  test "empty buckets in the middle are emitted contiguously (fill :nil)" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: :nil)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, nil}, {2_000, nil}]
  end

  test "fill :forward carries the last aggregate into empty buckets" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, fill: :forward)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 3_200, 9)

    assert StreamingResampler.finalized(pid) == [{0, 5}, {1_000, 5}, {2_000, 5}]
  end

  test ":last respects timestamp order even for out-of-order arrivals" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :last, allowed_lateness: 1_000)

    StreamingResampler.push(pid, 100, 1)
    StreamingResampler.push(pid, 900, 2)
    StreamingResampler.push(pid, 500, 3)
    StreamingResampler.flush(pid)

    # within bucket 0 the latest timestamp is 900 -> value 2
    assert StreamingResampler.finalized(pid) == [{0, 2}]
  end

  test "stats reports watermark and open bucket count" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 1_200, 7)

    stats = StreamingResampler.stats(pid)
    assert stats.watermark == 1_200
    # bucket 0 closed, bucket 1000 open
    assert stats.open_buckets == 1
  end

  test "finalized/flush/stats before any push" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    assert StreamingResampler.finalized(pid) == []
    assert StreamingResampler.flush(pid) == []
    assert StreamingResampler.stats(pid).watermark == nil
  end

  test "points after flush that map to emitted buckets are late drops" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    StreamingResampler.push(pid, 0, 5)
    StreamingResampler.push(pid, 900, 5)
    StreamingResampler.flush(pid)

    :ok = StreamingResampler.push(pid, 100, 99)
    assert StreamingResampler.stats(pid).late_dropped == 1
    assert StreamingResampler.finalized(pid) == [{0, 10}]
  end

  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(0) end
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(1_000, agg: :median) end

    assert_raise ArgumentError, fn ->
      StreamingResampler.start_link(1_000, allowed_lateness: -1)
    end
  end
end