  test "memory stays bounded while streaming a large file", %{path: path} do
    n = 50_000
    pad = String.duplicate("x", 240)

    File.open!(path, [:write], fn io ->
      IO.write(io, "[\n")

      Enum.each(1..n, fn i ->
        line = JSON.encode!(%{"id" => i, "value" => pad})
        sep = if i == n, do: "\n", else: ",\n"
        IO.write(io, line <> sep)
      end)

      IO.write(io, "]\n")
    end)

    file_size = File.stat!(path).size
    assert file_size > 5_000_000

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    {:ok, peak} = Agent.start_link(fn -> 0 end)

    handler = fn _item ->
      seen = Agent.get_and_update(counter, fn s -> {s + 1, s + 1} end)
      if rem(seen, 5_000) == 0, do: Agent.update(peak, &max(&1, :erlang.memory(:total)))
    end

    :erlang.garbage_collect()
    baseline = :erlang.memory(:total)

    assert {:ok, stats} = ParallelJsonStreamer.process(path, handler, max_concurrency: 8)

    assert stats.processed == n
    assert Agent.get(counter, & &1) == n

    growth = Agent.get(peak, & &1) - baseline
    assert growth < file_size
    assert is_float(stats.throughput) and stats.throughput > 0.0
  end