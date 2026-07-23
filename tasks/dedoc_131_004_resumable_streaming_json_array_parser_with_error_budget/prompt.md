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
defmodule ResumableJsonStreamer do
  def process(file_path, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    max_errors = Keyword.get(opts, :max_errors, :infinity)
    resume_from = Keyword.get(opts, :resume_from, 0)
    start = System.monotonic_time(:microsecond)

    init = %{processed: 0, errors: 0, index: 0, aborted: false}

    result =
      file_path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 in ["", "[", "]"]))
      |> Enum.reduce_while(init, fn line, acc ->
        step(line, %{acc | index: acc.index + 1}, handler_fn, resume_from, max_errors)
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: result.processed,
      errors: result.errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(result.processed, elapsed_ms),
      last_index: result.index,
      aborted: result.aborted
    }

    if result.aborted do
      {:error, :too_many_errors, stats}
    else
      {:ok, stats}
    end
  end

  defp step(_line, %{index: index} = acc, _handler_fn, resume_from, _max_errors)
       when index <= resume_from do
    {:cont, acc}
  end

  defp step(line, acc, handler_fn, _resume_from, max_errors) do
    case decode_line(line) do
      {:ok, item} ->
        handler_fn.(item)
        {:cont, %{acc | processed: acc.processed + 1}}

      {:error, _reason} ->
        errors = acc.errors + 1
        acc = %{acc | errors: errors}

        if exceeds?(errors, max_errors) do
          {:halt, %{acc | aborted: true}}
        else
          {:cont, acc}
        end
    end
  end

  defp exceeds?(_errors, :infinity), do: false
  defp exceeds?(errors, max) when is_integer(max), do: errors > max

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
