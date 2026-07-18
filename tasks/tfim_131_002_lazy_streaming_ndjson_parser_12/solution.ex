  test "memory stays bounded while streaming a large file", %{path: path} do
    n = 50_000
    pad = String.duplicate("x", 240)

    File.open!(path, [:write], fn io ->
      Enum.each(1..n, fn i ->
        IO.write(io, JSON.encode!(%{"id" => i, "value" => pad}) <> "\n")
      end)
    end)

    file_size = File.stat!(path).size
    assert file_size > 5_000_000

    {:ok, peak} = Agent.start_link(fn -> 0 end)

    :erlang.garbage_collect()
    baseline = :erlang.memory(:total)

    count =
      path
      |> NdjsonStreamer.stream()
      |> Enum.reduce(0, fn {:ok, _item}, seen ->
        seen = seen + 1

        if rem(seen, 5_000) == 0 do
          Agent.update(peak, &max(&1, :erlang.memory(:total)))
        end

        seen
      end)

    assert count == n

    growth = Agent.get(peak, & &1) - baseline
    assert growth < file_size
  end