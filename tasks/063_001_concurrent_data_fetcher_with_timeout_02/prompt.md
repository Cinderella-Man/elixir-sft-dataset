Implement the public `fetch_all/2` function (specifically the second clause, for
a non-empty list of sources). It receives `sources` — a list of `{name, fetch_fn}`
tuples where `name` is any term and `fetch_fn` is a zero-arity function — and
`timeout_ms`, a non-negative integer giving a single global wall-clock budget
shared across every fetch.

The function must spawn every fetch concurrently so they all start at the same
instant (use `Task.async/1`, keeping each `Task` paired with its source `name`),
running each `fetch_fn` through the `safe_call/1` helper so raises and unexpected
return values are normalised. It must then wait for all tasks under the single
global timeout using `Task.yield_many/2` — the budget is not re-applied per
source. For each task, reconcile its outcome into a result tuple: a successful
completion yields `{:ok, value}`, an application-level `{:error, reason}` is
preserved, a task that exited/raised becomes `{:error, reason}`, and a task that
did not finish in time must be shut down immediately with `Task.shutdown/2` using
`:brutal_kill` (so no zombie processes remain) and reported as
`{:error, :timeout}`. Finally, rebuild and return a map of `%{name => result_tuple}`
keyed by each source's original `name`.

```elixir
defmodule ConcurrentFetcher do
  @moduledoc """
  Fetches data from multiple sources concurrently under a single global timeout.

  All fetches begin at the same instant. The timeout budget is shared — it is
  not reset or re-applied per source. Any source that has not completed by the
  time the deadline fires is killed immediately and reported as
  `{:error, :timeout}`.
  """

  @doc """
  Fetch from all sources concurrently, returning results within `timeout_ms`.

  ## Parameters
  - `sources`    – list of `{name, fetch_fn}` tuples.
                   `name` is any term; `fetch_fn` is a zero-arity function
                   returning `{:ok, value}` or `{:error, reason}` (raising is
                   also handled gracefully).
  - `timeout_ms` – global wall-clock budget in milliseconds, shared by every
                   concurrent fetch.

  ## Return value
  A map of `%{name => result_tuple}` where each value is one of:

  - `{:ok, value}`          – fetch completed successfully within the timeout
  - `{:error, :timeout}`    – global timeout expired before this fetch finished
  - `{:error, reason}`      – fetch function raised or returned `{:error, reason}`

  Returns `%{}` immediately when `sources` is empty.
  """
  @spec fetch_all([{term(), (-> {:ok, term()} | {:error, term()})}], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms)
      when is_list(sources) and is_integer(timeout_ms) and timeout_ms >= 0 do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Wraps the user-supplied fetch function so that any exception or unexpected
  # return value is normalised into {:ok, _} | {:error, _} without leaking raw
  # EXIT signals to the caller.
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