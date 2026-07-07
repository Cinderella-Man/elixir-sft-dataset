defmodule ParallelJsonStreamerTest do
  use ExUnit.Case, async: false

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
        "parallel_json_#{System.pid()}_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    {:ok, collector} = Collector.start_link()
    %{path: path, collector: collector}
  end

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
  # Correctness + ordering under concurrency
  # -------------------------------------------------------

  test "processes every item in a well-formed file", %{path: path, collector: c} do
    write_array(path, for(i <- 1..25, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 25
    assert stats.errors == 0
    assert Collector.count(c) == 25
  end

  test "handler is invoked in file order despite concurrent decode", %{path: path, collector: c} do
    write_array(path, for(i <- 1..500, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 8)

    assert stats.processed == 500
    assert Enum.map(Collector.items(c), & &1["id"]) == Enum.to_list(1..500)
  end

  test "reports the effective max_concurrency", %{path: path, collector: c} do
    write_array(path, for(i <- 1..3, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 3)

    assert stats.max_concurrency == 3

    {:ok, c2} = Collector.start_link()
    assert {:ok, dstats} = ParallelJsonStreamer.process(path, Collector.handler(c2))
    assert dstats.max_concurrency == System.schedulers_online()
  end

  test "works with max_concurrency: 1 and preserves order", %{path: path, collector: c} do
    write_array(path, for(i <- 1..10, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 1)

    assert stats.processed == 10
    assert Enum.map(Collector.items(c), & &1["id"]) == Enum.to_list(1..10)
  end

  test "decodes different JSON value shapes in order", %{path: path, collector: c} do
    write_array(path, [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 6

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

    assert {:ok, stats} = ParallelJsonStreamer.process(path, Collector.handler(c))
    assert stats.processed == 0
    assert stats.errors == 0
    assert Collector.count(c) == 0
  end

  # -------------------------------------------------------
  # Malformed entries
  # -------------------------------------------------------

  test "skips malformed entries mid-stream and keeps order of the rest", %{
    path: path,
    collector: c
  } do
    encoded =
      for i <- 1..10 do
        if i in [3, 7], do: "{not valid json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 8
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 4, 5, 6, 8, 9, 10]
  end

  test "malformed entries never invoke the handler", %{path: path, collector: c} do
    write_array(path, [
      valid(%{"id" => 1}),
      "definitely : not json",
      valid(%{"id" => 2}),
      "[1, 2,",
      valid(%{"id" => 3})
    ])

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 4)

    assert stats.processed == 3
    assert stats.errors == 2
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "reports well-formed stats", %{path: path, collector: c} do
    write_array(path, for(i <- 1..1_000, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ParallelJsonStreamer.process(path, Collector.handler(c), max_concurrency: 8)

    assert stats.processed == 1_000
    assert stats.errors == 0
    assert is_number(stats.elapsed_ms) and stats.elapsed_ms >= 0
    assert is_float(stats.throughput) and stats.throughput >= 0.0
  end

  # -------------------------------------------------------
  # Bounded memory
  # -------------------------------------------------------

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
end
