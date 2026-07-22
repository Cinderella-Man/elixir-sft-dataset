# Implement `fetch_all/2`

Implement the public `fetch_all/2` function, the module's only entry point. It
takes `sources` (a list of `{name, fetch_fns}` tuples, where `name` is any term
and `fetch_fns` is an ordered list of zero-arity fallback functions) and
`timeout_ms` (a single global wall-clock budget shared across every source).

It must:

- Return `%{}` immediately when `sources` is empty.
- Otherwise, start **every** source concurrently the moment it is called by
  spawning a `Task.async/1` per source that runs that source's fallback chain
  via the private `run_chain/2` helper (starting with an empty accumulator).
  Keep each spawned task associated with its source `name`.
- Wait for all tasks under the **shared** `timeout_ms` deadline (not per-source,
  not per-fallback) using `Task.yield_many/2`, and turn each task's outcome into
  a result tuple:
  - `{:ok, {:ok, value}}` → `{:ok, value}` (a fallback succeeded in time).
  - `{:ok, {:error, reasons}}` → `{:error, {:all_failed, reasons}}` (the chain
    was exhausted; `reasons` are in attempt order).
  - `{:exit, reason}` → `{:error, reason}`.
  - `nil` (the task did not finish before the deadline) → forcibly kill the task
    with `Task.shutdown(task, :brutal_kill)` so no zombie process survives, then
    `{:error, :timeout}`.
- Return only after every spawned process has finished or been confirmed dead,
  producing a `%{name => result_tuple}` map that preserves each original source
  `name` (which may repeat or be any term) as its key.

Guard the main clause so it only accepts a list of sources and a non-negative
integer timeout.

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
  def fetch_all(sources, timeout_ms) do
    # TODO
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