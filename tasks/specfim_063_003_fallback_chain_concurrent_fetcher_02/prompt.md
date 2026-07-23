# Fill in one @spec

Below: a working module where the `@spec` for
`fetch_all/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `fetch_all/2` missing

```elixir
defmodule FallbackFetcher do
  @moduledoc """
  Fetches from multiple sources concurrently under a single global timeout,
  where each source carries an ordered chain of fallback functions.

  Sources run concurrently with one another; within a source the fallbacks are
  attempted sequentially until one succeeds or the chain is exhausted. Any
  source still working when the shared deadline fires is killed and reported as
  `{:error, :timeout}`.
  """

  @doc """
  Fetch from all sources concurrently, returning within `timeout_ms`.

  Returns `%{name => result_tuple}` where each value is `{:ok, value}`,
  `{:error, {:all_failed, reasons}}`, or `{:error, :timeout}`.
  """
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
