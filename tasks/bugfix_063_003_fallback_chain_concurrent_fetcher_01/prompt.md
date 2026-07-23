# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Fallback-Chain Concurrent Fetcher

Write me an Elixir module called `FallbackFetcher` that fetches data from multiple sources concurrently, where **each source carries an ordered chain of fallback functions** that are tried in sequence until one succeeds, all under a single global timeout.

I need this function in the public API:

- `FallbackFetcher.fetch_all(sources, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fns}` tuples. `name` can be any term (atom, string, tuple, etc.).
  - `fetch_fns` is a list of zero-arity functions (the fallback chain). Each function either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `timeout_ms` is a single global wall-clock budget shared across every source.

Behaviour:

- Every source runs **concurrently** with every other source, starting the moment `fetch_all` is called.
- **Within a single source**, the fallback functions are tried **sequentially, in order**: try the first; if it returns `{:ok, value}`, that source is done with `{:ok, value}`; if it returns `{:error, reason}` or raises, move on to the next function; continue until one succeeds or the chain is exhausted.
- The function returns a map of `%{name => result_tuple}` where each value is one of:
  - `{:ok, value}` — some fallback in the chain succeeded within the timeout.
  - `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons` is the list of failure reasons in the order the functions were tried (a raised exception is captured as its exception struct).
  - `{:error, :timeout}` — the global timeout expired while this source was still working through its chain.

Rules:

- The global timeout is shared across all sources, not per-source and not per-fallback. A source whose chain (summed sequentially) overruns the deadline is reported as `{:error, :timeout}`.
- When the timeout fires, any source still working must be killed immediately — no zombie processes. The function returns only after all spawned processes are done or confirmed dead.
- If `sources` is empty, return `%{}` immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.

## The buggy module

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
              {:error, value}

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

## Failing test report

```
6 of 9 test(s) failed:

  * test uses the first fallback when it succeeds
      
      
      Assertion with == failed
      code:  assert result[:a] == {:ok, :first}
      left:  {:error, :first}
      right: {:ok, :first}
      

  * test falls through to the next fallback on error
      
      
      Assertion with == failed
      code:  assert result[:a] == {:ok, :backup}
      left:  {:error, :backup}
      right: {:ok, :backup}
      

  * test treats a raising fallback as a failure and continues
      
      
      Assertion with == failed
      code:  assert result[:a] == {:ok, :recovered}
      left:  {:error, :recovered}
      right: {:ok, :recovered}
      

  * test a chain that overruns the global timeout is reported as :timeout
      
      
      Assertion with == failed
      code:  assert result[:fast] == {:ok, :done}
      left:  {:error, :done}
      right: {:ok, :done}
      

  (…2 more)
```
