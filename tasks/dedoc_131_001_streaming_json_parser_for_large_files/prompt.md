# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule JsonStreamer do
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
