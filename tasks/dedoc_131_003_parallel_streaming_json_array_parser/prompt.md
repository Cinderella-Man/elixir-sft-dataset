# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule ParallelJsonStreamer do
  def process(file_path, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    start = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 in ["", "[", "]"]))
      |> Task.async_stream(&decode_line/1,
        max_concurrency: max_concurrency,
        ordered: true
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, {:ok, item}}, {p, e} ->
          handler_fn.(item)
          {p + 1, e}

        {:ok, {:error, _reason}}, {p, e} ->
          {p, e + 1}
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: processed,
      errors: errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(processed, elapsed_ms),
      max_concurrency: max_concurrency
    }

    {:ok, stats}
  end

  defp decode_line(trimmed) do
    trimmed
    |> strip_trailing_comma()
    |> JSON.decode()
  end

  defp strip_trailing_comma(text) do
    case String.ends_with?(text, ",") do
      true -> String.slice(text, 0..-2//1)
      false -> text
    end
  end

  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```
