# Task: Implement `run_chain/2`

Implement the private `run_chain/2` function for the `FallbackFetcher` module.

`run_chain/2` drives a single source's ordered fallback chain. It takes a list of
zero-arity fallback functions and an accumulator of failure reasons (built up in
reverse, i.e. most-recent-first), and tries each fallback in order:

- **Base case** — when the list of fallbacks is empty, the chain is exhausted:
  return `{:error, reasons}` where `reasons` is the accumulated failure reasons
  restored to attempt order (the accumulator is reversed before returning).
- **Recursive case** — for the head fallback function and the remaining `rest`:
  invoke the head via `safe_call/1` (which normalises any exception/throw/exit/
  unexpected return into a tagged tuple so it can never crash the caller).
  - If `safe_call/1` returns `{:ok, value}`, that fallback succeeded — return the
    `{:ok, value}` tuple immediately without trying any further fallbacks.
  - If it returns `{:error, reason}`, prepend `reason` onto the accumulator and
    recurse over `rest`, continuing down the chain.

The accumulator starts as `[]` (see the `Task.async(fn -> run_chain(fetch_fns, []) end)`
call in `fetch_all/2`), so on exhaustion the reasons must be reversed to reflect the
order the functions were actually tried.

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
  @spec fetch_all([{term(), [(-> {:ok, term()} | {:error, term()})]}], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
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
  defp run_chain(fetch_fns, reasons) do
    # TODO
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