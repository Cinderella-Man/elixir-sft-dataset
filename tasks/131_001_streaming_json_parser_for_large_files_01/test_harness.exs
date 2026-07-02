defmodule JsonStreamerTest do
  use ExUnit.Case, async: false

  # --- Inline helper: accumulates items passed to the handler ---
  defmodule Collector do
    use Agent

    def start_link(_opts \\ []), do: Agent.start_link(fn -> [] end)

    def handler(pid), do: fn item -> Agent.update(pid, &[item | &1]) end

    def items(pid), do: Agent.get(pid, &Enum.reverse/1)
    def count(pid), do: Agent.get(pid, &length/1)
  end

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "json_streamer_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    {:ok, collector} = Collector.start_link()

    %{path: path, collector: collector}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Writes a JSON array file, one raw element string per line. Elements are
  # written verbatim (so callers can inject malformed lines), with the correct
  # trailing-comma layout. `raw_elements` is a list of already-serialized lines.
  defp write_array(path, raw_elements) do
    body =
      case raw_elements do
        [] ->
          "[\n]\n"

        elems ->
          last = length(elems) - 1

          inner =
            elems
            |> Enum.with_index()
            |> Enum.map_join("\n", fn {enc, idx} ->
              if idx == last, do: enc, else: enc <> ","
            end)

          "[\n" <> inner <> "\n]\n"
      end

    File.write!(path, body)
  end

  defp valid(item), do: JSON.encode!(item)

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "processes every item in a well-formed file", %{path: path, collector: c} do
    encoded = for i <- 1..25, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 25
    assert stats.errors == 0
    assert Collector.count(c) == 25
  end

  test "handler receives fully decoded items with string keys", %{path: path, collector: c} do
    encoded = for i <- 1..5, do: valid(%{"id" => i, "value" => "item-#{i}"})
    write_array(path, encoded)

    assert {:ok, _stats} = JsonStreamer.process(path, Collector.handler(c))

    expected = for i <- 1..5, do: %{"id" => i, "value" => "item-#{i}"}
    assert Collector.items(c) == expected
  end

  test "decodes different JSON value shapes", %{path: path, collector: c} do
    encoded = [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ]

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 6
    assert stats.errors == 0

    assert Collector.items(c) == [
             %{"kind" => "object"},
             [1, 2, 3],
             "a string",
             42,
             true,
             nil
           ]
  end

  # -------------------------------------------------------
  # Empty array
  # -------------------------------------------------------

  test "empty array yields zero processed and zero errors", %{path: path, collector: c} do
    write_array(path, [])

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 0
    assert stats.errors == 0
    assert Collector.count(c) == 0
  end

  # -------------------------------------------------------
  # Malformed entries
  # -------------------------------------------------------

  test "skips a malformed entry mid-stream and continues", %{path: path, collector: c} do
    encoded =
      for i <- 1..10 do
        if i in [3, 7], do: "{not valid json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 8
    assert stats.errors == 2

    ids = Enum.map(Collector.items(c), & &1["id"])
    assert ids == [1, 2, 4, 5, 6, 8, 9, 10]
  end

  test "handles a file that is entirely malformed", %{path: path, collector: c} do
    encoded = for _ <- 1..6, do: "}}}garbage{{{"
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 0
    assert stats.errors == 6
    assert Collector.count(c) == 0
  end

  test "malformed entries never invoke the handler", %{path: path, collector: c} do
    encoded = [
      valid(%{"id" => 1}),
      "definitely : not json",
      valid(%{"id" => 2}),
      "[1, 2,",
      valid(%{"id" => 3})
    ]

    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 3
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end

  # -------------------------------------------------------
  # Stats: elapsed + throughput
  # -------------------------------------------------------

  test "reports well-formed stats", %{path: path, collector: c} do
    encoded = for i <- 1..1_000, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert is_integer(stats.processed) and stats.processed == 1_000
    assert is_integer(stats.errors) and stats.errors == 0

    assert is_number(stats.elapsed_ms)
    assert stats.elapsed_ms >= 0

    assert is_float(stats.throughput)
    assert stats.throughput >= 0.0
  end

  # -------------------------------------------------------
  # Memory stays bounded while streaming a large file
  # -------------------------------------------------------

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
end