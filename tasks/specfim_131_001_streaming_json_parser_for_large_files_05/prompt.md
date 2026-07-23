# Fill in one @spec

Below: a working module where the `@spec` for
`throughput/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `throughput/2` missing

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

  # TODO: @spec
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```

The `@spec` attribute only — nothing more.
