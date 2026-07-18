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
defmodule FallbackFetcher do
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms)
      when is_list(sources) and is_integer(timeout_ms) and timeout_ms >= 0 do
    tagged =
      Enum.map(sources, fn {name, fetch_fns} ->
        task = Task.async(fn -> run_chain(fetch_fns, []) end)
        {name, task}
      end)

    tasks = Enum.map(tagged, fn {_name, task} -> task end)
    yields = Task.yield_many(tasks, timeout_ms)

    ref_to_result =
      Enum.reduce(yields, %{}, fn {task, outcome}, acc ->
        result =
          case outcome do
            {:ok, {:ok, value}} ->
              {:ok, value}

            {:ok, {:error, reasons}} ->
              {:error, {:all_failed, reasons}}

            {:exit, reason} ->
              {:error, reason}

            nil ->
              Task.shutdown(task, :brutal_kill)
              {:error, :timeout}
          end

        Map.put(acc, task.ref, result)
      end)

    Map.new(tagged, fn {name, task} -> {name, Map.fetch!(ref_to_result, task.ref)} end)
  end

  # Tries each fallback in order. Returns `{:ok, value}` on the first success,
  # or `{:error, reasons}` (reasons in attempt order) if the chain is exhausted.
  defp run_chain([], reasons), do: {:error, Enum.reverse(reasons)}

  defp run_chain([fetch_fn | rest], reasons) do
    case safe_call(fetch_fn) do
      {:ok, _} = ok -> ok
      {:error, reason} -> run_chain(rest, [reason | reasons])
    end
  end

  # Normalises any exception, throw, exit, or unexpected return into a tagged
  # `{:ok, _} | {:error, _}` tuple so a fallback can never crash the caller.
  defp safe_call(fetch_fn) do
    case fetch_fn.() do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, value -> {:error, {kind, value}}
  end
end
```
