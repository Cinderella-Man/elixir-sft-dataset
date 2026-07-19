# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ResumableJsonStreamerTest do
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
        "resumable_json_#{System.pid()}_#{System.unique_integer([:positive])}.json"
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
  # Happy path
  # -------------------------------------------------------

  test "clean run processes everything, aborted false", %{path: path, collector: c} do
    write_array(path, for(i <- 1..25, do: valid(%{"id" => i})))

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 25
    assert stats.errors == 0
    assert stats.last_index == 25
    assert stats.aborted == false
    assert Collector.count(c) == 25
  end

  test "empty array examines nothing", %{path: path, collector: c} do
    write_array(path, [])

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))
    assert stats.processed == 0
    assert stats.errors == 0
    assert stats.last_index == 0
    assert stats.aborted == false
  end

  # -------------------------------------------------------
  # Error budget under :infinity (default) tolerates all
  # -------------------------------------------------------

  test "default :infinity tolerates malformed items and continues", %{path: path, collector: c} do
    encoded =
      for i <- 1..10 do
        if i in [3, 7], do: "{not valid json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))
    assert stats.processed == 8
    assert stats.errors == 2
    assert stats.aborted == false
    assert stats.last_index == 10
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 4, 5, 6, 8, 9, 10]
  end

  # -------------------------------------------------------
  # Strict error budget aborts
  # -------------------------------------------------------

  test "max_errors: 0 aborts on the first malformed item", %{path: path, collector: c} do
    encoded =
      for i <- 1..10 do
        if i == 4, do: "garbage(((", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:error, :too_many_errors, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 0)

    assert stats.aborted == true
    assert stats.errors == 1
    assert stats.processed == 3
    assert stats.last_index == 4
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end

  test "max_errors: 2 aborts on the third malformed item", %{path: path, collector: c} do
    encoded =
      for i <- 1..12 do
        if i in [2, 5, 9], do: "]][[", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:error, :too_many_errors, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 2)

    assert stats.aborted == true
    assert stats.errors == 3
    assert stats.last_index == 9
    # Processed items 1, 3, 4, 6, 7, 8 (before the 3rd error at index 9).
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 3, 4, 6, 7, 8]
  end

  # -------------------------------------------------------
  # Resume
  # -------------------------------------------------------

  test "resume_from skips element lines without decoding or handling them", %{
    path: path,
    collector: c
  } do
    write_array(path, for(i <- 1..10, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 4)

    assert stats.processed == 6
    assert stats.errors == 0
    assert stats.last_index == 10
    assert Enum.map(Collector.items(c), & &1["id"]) == [5, 6, 7, 8, 9, 10]
  end

  test "resume_from past the end processes nothing", %{path: path, collector: c} do
    write_array(path, for(i <- 1..5, do: valid(%{"id" => i})))

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 100)

    assert stats.processed == 0
    assert stats.last_index == 5
    assert Collector.count(c) == 0
  end

  test "abort then resume past the poison line completes the run", %{path: path} do
    encoded =
      for i <- 1..10 do
        if i == 4, do: "{broken", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    {:ok, c1} = Collector.start_link()

    assert {:error, :too_many_errors, s1} =
             ResumableJsonStreamer.process(path, Collector.handler(c1), max_errors: 0)

    assert s1.last_index == 4
    assert Enum.map(Collector.items(c1), & &1["id"]) == [1, 2, 3]

    {:ok, c2} = Collector.start_link()

    assert {:ok, s2} =
             ResumableJsonStreamer.process(path, Collector.handler(c2),
               resume_from: s1.last_index,
               max_errors: 0
             )

    assert s2.aborted == false
    assert s2.processed == 6
    assert Enum.map(Collector.items(c2), & &1["id"]) == [5, 6, 7, 8, 9, 10]
  end

  # -------------------------------------------------------
  # Stats
  # -------------------------------------------------------

  test "reports well-formed stats on a clean run", %{path: path, collector: c} do
    write_array(path, for(i <- 1..1_000, do: valid(%{"id" => i})))

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

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

    assert {:ok, stats} = ResumableJsonStreamer.process(path, handler)

    assert stats.processed == n
    assert Agent.get(counter, & &1) == n

    growth = Agent.get(peak, & &1) - baseline
    assert growth < file_size
    assert is_float(stats.throughput) and stats.throughput > 0.0
  end

  test "max_errors: 2 with exactly two malformed items finishes cleanly", %{
    path: path,
    collector: c
  } do
    encoded =
      for i <- 1..8 do
        if i in [2, 5], do: "{{{not json", else: valid(%{"id" => i})
      end

    write_array(path, encoded)

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), max_errors: 2)

    assert stats.aborted == false
    assert stats.errors == 2
    assert stats.processed == 6
    assert stats.last_index == 8
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 3, 4, 6, 7, 8]
  end

  test "blank lines are not element lines for indexing or resume", %{path: path, collector: c} do
    File.write!(path, "[\n\n{\"id\": 1},\n\n\n{\"id\": 2},\n{\"id\": 3}\n\n]\n")

    assert {:ok, stats} =
             ResumableJsonStreamer.process(path, Collector.handler(c), resume_from: 1)

    assert stats.processed == 2
    assert stats.errors == 0
    assert stats.last_index == 3
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [2, 3]
  end

  test "element lines padded with whitespace still decode", %{path: path, collector: c} do
    File.write!(path, "[\n   {\"id\": 1},  \n\t{\"id\": 2}\t\n]\n")

    assert {:ok, stats} = ResumableJsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert stats.last_index == 2
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end

  test "handler return values do not affect the run", %{path: path, collector: c} do
    write_array(path, for(i <- 1..3, do: valid(%{"id" => i})))

    handler = fn item ->
      Agent.update(c, &[item | &1])
      {:error, :handler_says_no}
    end

    assert {:ok, stats} = ResumableJsonStreamer.process(path, handler)

    assert stats.processed == 3
    assert stats.errors == 0
    assert stats.aborted == false
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3]
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
