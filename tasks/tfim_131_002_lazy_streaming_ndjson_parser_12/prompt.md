# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule NdjsonStreamer do
  @moduledoc """
  Lazy streaming parser for very large NDJSON (newline-delimited JSON) files.

  Unlike an eager parser that folds over the file and calls a handler,
  `stream/1` returns a plain lazy `Enumerable`. Callers compose it with
  `Stream`/`Enum` functions and decide themselves what to do with malformed
  lines, which surface inline as `{:error, {:invalid_json, raw}}` elements.

  The file is read lazily with `File.stream!/2`, so only a single line (plus its
  decoded value) is ever in memory, regardless of file size.

  Expected layout — one complete JSON value per line, no brackets, no commas:

      {"id":1,"value":"a"}
      {"id":2,"value":"b"}
      {"id":3,"value":"c"}
  """

  @type result :: {:ok, term()} | {:error, {:invalid_json, String.t()}}

  @doc """
  Returns a lazy enumerable yielding one `t:result/0` per non-blank line.

  Blank lines (empty after trimming) are dropped and produce no element.
  Nothing is read from disk until the returned stream is enumerated, and only
  as far as it is consumed.
  """
  @spec stream(Path.t()) :: Enumerable.t()
  def stream(file_path) do
    file_path
    |> File.stream!(:line, [])
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
  end

  @doc """
  Decodes a single line, returning `{:ok, value}` or
  `{:error, {:invalid_json, raw}}`. Never raises on malformed input.
  """
  @spec decode_line(String.t()) :: result()
  def decode_line(line) do
    trimmed = String.trim(line)

    case JSON.decode(trimmed) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, {:invalid_json, trimmed}}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule NdjsonStreamerTest do
  use ExUnit.Case, async: false

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "ndjson_streamer_#{System.pid()}_#{System.unique_integer([:positive])}.ndjson"
      )

    on_exit(fn -> File.rm(path) end)

    %{path: path}
  end

  # Writes one raw line per element, verbatim (so malformed lines can be injected).
  defp write_lines(path, raw_lines) do
    File.write!(path, Enum.map_join(raw_lines, "\n", & &1) <> "\n")
  end

  defp valid(item), do: JSON.encode!(item)

  # -------------------------------------------------------
  # stream/1 is lazy
  # -------------------------------------------------------

  test "stream/1 returns a lazy enumerable, not a list", %{path: path} do
    write_lines(path, for(i <- 1..5, do: valid(%{"id" => i})))

    stream = NdjsonStreamer.stream(path)

    refute is_list(stream)
    assert match?(%Stream{}, stream) or is_function(stream)
  end

  test "composes with Stream.take without forcing the whole file", %{path: path} do
    write_lines(path, for(i <- 1..1000, do: valid(%{"id" => i})))

    first_three =
      path
      |> NdjsonStreamer.stream()
      |> Stream.take(3)
      |> Enum.to_list()

    assert first_three == [
             {:ok, %{"id" => 1}},
             {:ok, %{"id" => 2}},
             {:ok, %{"id" => 3}}
           ]
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "yields {:ok, value} for every well-formed line", %{path: path} do
    write_lines(path, for(i <- 1..25, do: valid(%{"id" => i})))

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert length(results) == 25
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.map(results, fn {:ok, v} -> v["id"] end) == Enum.to_list(1..25)
  end

  test "decodes objects into string-keyed maps", %{path: path} do
    write_lines(path, for(i <- 1..3, do: valid(%{"id" => i, "value" => "item-#{i}"})))

    values =
      path
      |> NdjsonStreamer.stream()
      |> Enum.map(fn {:ok, v} -> v end)

    assert values == [
             %{"id" => 1, "value" => "item-1"},
             %{"id" => 2, "value" => "item-2"},
             %{"id" => 3, "value" => "item-3"}
           ]
  end

  test "decodes different JSON value shapes", %{path: path} do
    write_lines(path, [
      valid(%{"kind" => "object"}),
      valid([1, 2, 3]),
      valid("a string"),
      valid(42),
      valid(true),
      valid(nil)
    ])

    values = path |> NdjsonStreamer.stream() |> Enum.map(fn {:ok, v} -> v end)

    assert values == [%{"kind" => "object"}, [1, 2, 3], "a string", 42, true, nil]
  end

  # -------------------------------------------------------
  # Blank lines produce no elements
  # -------------------------------------------------------

  test "blank lines are skipped entirely (no element emitted)", %{path: path} do
    File.write!(path, "\n" <> valid(%{"id" => 1}) <> "\n\n   \n" <> valid(%{"id" => 2}) <> "\n\n")

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert results == [{:ok, %{"id" => 1}}, {:ok, %{"id" => 2}}]
  end

  test "empty file yields an empty stream", %{path: path} do
    File.write!(path, "")

    assert path |> NdjsonStreamer.stream() |> Enum.to_list() == []
  end

  # -------------------------------------------------------
  # Malformed lines surface inline and don't abort
  # -------------------------------------------------------

  test "malformed line surfaces as {:error, {:invalid_json, raw}} and continues", %{path: path} do
    write_lines(path, [
      valid(%{"id" => 1}),
      "{not valid json",
      valid(%{"id" => 2})
    ])

    results = path |> NdjsonStreamer.stream() |> Enum.to_list()

    assert results == [
             {:ok, %{"id" => 1}},
             {:error, {:invalid_json, "{not valid json"}},
             {:ok, %{"id" => 2}}
           ]
  end

  test "caller can partition ok/error using ordinary stream functions", %{path: path} do
    write_lines(path, [
      valid(%{"id" => 1}),
      "garbage(((",
      valid(%{"id" => 2}),
      "]][[",
      valid(%{"id" => 3})
    ])

    {oks, errors} =
      path
      |> NdjsonStreamer.stream()
      |> Enum.split_with(&match?({:ok, _}, &1))

    assert Enum.map(oks, fn {:ok, v} -> v["id"] end) == [1, 2, 3]
    assert length(errors) == 2
    assert Enum.all?(errors, &match?({:error, {:invalid_json, _}}, &1))
  end

  # -------------------------------------------------------
  # decode_line/1 directly
  # -------------------------------------------------------

  test "decode_line/1 decodes and reports errors without raising" do
    assert NdjsonStreamer.decode_line(~s({"id":1})) == {:ok, %{"id" => 1}}
    assert NdjsonStreamer.decode_line("  42  ") == {:ok, 42}
    assert NdjsonStreamer.decode_line("nope") == {:error, {:invalid_json, "nope"}}
  end

  # -------------------------------------------------------
  # Memory stays bounded while streaming a large file
  # -------------------------------------------------------

  test "memory stays bounded while streaming a large file", %{path: path} do
    # TODO
  end
end
```
