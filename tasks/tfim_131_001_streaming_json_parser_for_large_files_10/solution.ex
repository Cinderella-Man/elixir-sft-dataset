  test "memory stays bounded while streaming a large file", %{path: path} do
    n = 50_000
    pad = String.duplicate("x", 240)

    # Stream the file to disk so building it doesn't inflate test memory.
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
    # Sanity: the file should be several MB so the bound below is meaningful.
    assert file_size > 5_000_000

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    {:ok, peak} = Agent.start_link(fn -> 0 end)

    handler = fn _item ->
      seen = Agent.get_and_update(counter, fn seen -> {seen + 1, seen + 1} end)

      if rem(seen, 5_000) == 0 do
        Agent.update(peak, &max(&1, :erlang.memory(:total)))
      end
    end

    :erlang.garbage_collect()
    baseline = :erlang.memory(:total)

    assert {:ok, stats} = JsonStreamer.process(path, handler)

    assert stats.processed == n
    assert stats.errors == 0
    assert Agent.get(counter, & &1) == n

    peak_total = Agent.get(peak, & &1)
    growth = peak_total - baseline

    # A streaming implementation holds only one line at a time, so peak memory
    # growth must stay well under the full file size. Reading the whole file
    # into memory would blow past this bound.
    assert growth < file_size

    # Throughput should be a positive rate for a file this size.
    assert is_float(stats.throughput)
    assert stats.throughput > 0.0
  end