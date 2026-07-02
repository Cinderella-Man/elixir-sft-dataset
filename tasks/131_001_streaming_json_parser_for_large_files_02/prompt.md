# Streaming JSON Array Parser — implement `process/2`

Implement the public `process/2` function for `JsonStreamer`. It streams a very
large JSON array file line by line — decoding one item per line — without ever
loading the whole file into memory.

`process/2` receives a `file_path` and a one-arity `handler_fn` (guaranteed by the
guard to be a function of arity 1). It must:

- Record a monotonic start time using `System.monotonic_time(:microsecond)` before
  streaming begins.
- Read the file lazily with `File.stream!(file_path, [], :line)` so that only a
  single line is held in memory at a time.
- Fold over the lines with `Enum.reduce/3`, threading an accumulator of
  `{processed, errors}` starting at `{0, 0}`. For each line, trim surrounding
  whitespace with `String.trim/1` and delegate to the existing `handle_line/4`
  helper, which decodes the line, invokes `handler_fn` on success, and returns the
  updated `{processed, errors}` tuple.
- After the fold, compute the elapsed time: subtract the start time from a fresh
  `System.monotonic_time(:microsecond)` reading to get microseconds, convert to
  milliseconds by dividing by 1000, and clamp it to be `>= 0` with `max/2`.
- Build a `stats` map with `:processed`, `:errors`, `:elapsed_ms`, and
  `:throughput` (delegating the throughput calculation to the existing
  `throughput/2` helper, which guards against division by zero).
- Return `{:ok, stats}`.

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
    # TODO
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