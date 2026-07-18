# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule JsonStreamer do
  @moduledoc """
  Streaming parser for very large JSON array files.

  The parser processes a JSON array laid out one element per line without
  ever loading the whole file into memory. It reads the file lazily with
  `File.stream!/2` and folds over the lines, so at any moment only a single
  line (plus its decoded value) is held in memory.

  The expected file layout is:

      [
      {"id":1,"value":"a"},
      {"id":2,"value":"b"},
      {"id":3,"value":"c"}
      ]

  where the first line is `[`, the last line is `]`, and every element line
  ends with a trailing comma except the last one.
  """

  @type stats :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          elapsed_ms: number(),
          throughput: float()
        }

  @doc """
  Streams `file_path` line by line, decoding one JSON item per line.

  For every successfully decoded item, `handler_fn` is invoked exactly once
  with the decoded value (its return value is ignored). Malformed items are
  counted and skipped without aborting the stream.

  Returns `{:ok, stats}` where `stats` reports the number of processed and
  errored items, the elapsed wall-clock time in milliseconds, and the
  throughput in processed items per second.
  """
  @spec process(Path.t(), (term() -> term())) :: {:ok, stats()}
  def process(file_path, handler_fn) when is_function(handler_fn, 1) do
    start = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!(:line, [])
      |> Enum.reduce({0, 0}, fn line, {processed, errors} ->
        line
        |> String.trim()
        |> handle_line(handler_fn, processed, errors)
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: processed,
      errors: errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(processed, elapsed_ms)
    }

    {:ok, stats}
  end

  @spec handle_line(String.t(), (term() -> term()), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp handle_line(trimmed, _handler_fn, processed, errors)
       when trimmed in ["", "[", "]"] do
    {processed, errors}
  end

  defp handle_line(trimmed, handler_fn, processed, errors) do
    payload = strip_trailing_comma(trimmed)

    case JSON.decode(payload) do
      {:ok, item} ->
        handler_fn.(item)
        {processed + 1, errors}

      {:error, _reason} ->
        {processed, errors + 1}
    end
  end

  @spec strip_trailing_comma(String.t()) :: String.t()
  defp strip_trailing_comma(text) do
    case String.ends_with?(text, ",") do
      true -> String.slice(text, 0..-2//1)
      false -> text
    end
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```

## Test harness — implement the `# TODO` test

```elixir
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
        "json_streamer_#{System.pid()}_#{System.unique_integer([:positive])}.json"
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

  test "throughput equals processed divided by elapsed seconds", %{path: path, collector: c} do
    encoded = for i <- 1..500, do: valid(%{"id" => i})
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 500
    assert is_float(stats.throughput)

    expected =
      if stats.elapsed_ms == 0 or stats.elapsed_ms == 0.0 do
        0.0
      else
        stats.processed / (stats.elapsed_ms / 1000)
      end

    assert stats.throughput == expected
  end

  test "only one trailing comma is stripped from an element line", %{path: path, collector: c} do
    encoded = [valid("a,"), valid(%{"note" => "b,"}), valid("c,")]
    write_array(path, encoded)

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 3
    assert stats.errors == 0
    assert Collector.items(c) == ["a,", %{"note" => "b,"}, "c,"]
  end

  test "blank lines are skipped without counting as errors", %{path: path, collector: c} do
    File.write!(path, "[\n\n{\"id\":1},\n   \n{\"id\":2}\n\n]\n")

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end

  test "indented element lines are trimmed before decoding", %{path: path, collector: c} do
    File.write!(path, "  [  \n\t{\"id\":1},  \n   {\"id\":2}\t\n  ]  \n")

    assert {:ok, stats} = JsonStreamer.process(path, Collector.handler(c))

    assert stats.processed == 2
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2]
  end

  test "handler return values do not affect stats or streaming", %{path: path, collector: c} do
    encoded = for i <- 1..4, do: valid(%{"id" => i})
    write_array(path, encoded)

    collect = Collector.handler(c)

    handler = fn item ->
      collect.(item)
      {:error, :ignored_by_contract}
    end

    assert {:ok, stats} = JsonStreamer.process(path, handler)

    assert stats.processed == 4
    assert stats.errors == 0
    assert Enum.map(Collector.items(c), & &1["id"]) == [1, 2, 3, 4]
  end

  test "duplicate items each reach the handler exactly one time", %{path: path} do
    # TODO
  end
end
```
