# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Metrics` that collects **time-windowed event rates** using ETS for fast, concurrent-safe storage. Instead of a single monotonic total, this collector buckets events by the wall-clock second at which they occur, so you can ask "how many events happened in the last N seconds?".

To keep the collector testable, time must be **injectable**: `start_link` accepts a `:clock` option — a zero-arity function returning the current Unix time in integer seconds — defaulting to `fn -> System.system_time(:second) end`.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It accepts `:name` (process registration, default `__MODULE__`) and `:clock` (as above).
- `Metrics.increment(name, amount \\ 1)` to record `amount` events for `name` at the current second, returning `:ok`. `amount` must be a non-negative integer, enforced by a guard clause: a negative or non-integer `amount` raises `FunctionClauseError`, while an `amount` of `0` is accepted and records nothing. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS via `:ets.update_counter`, bumping the per-second bucket for `name`.
- `Metrics.rate(name, window_seconds)` to return the total number of events recorded for `name` within the last `window_seconds` — i.e. all events whose bucket second is strictly greater than `now - window_seconds`, where `now` comes from the injected clock. Returns `0` for an unknown name.
- `Metrics.count(name)` to return the all-time total number of events recorded for `name` across every bucket, or `0` if nothing has been recorded for `name`.
- `Metrics.reset(name)` to delete every bucket for `name`.
- `Metrics.prune(retention_seconds)` to delete all buckets (across every name) whose second is `<= now - retention_seconds`, returning the number of buckets deleted (not the number of events removed). This lets the table be bounded over time.
- `Metrics.all()` to return a map of `%{name => all_time_total}`, containing only names that currently have buckets.

The ETS table must be public and named so `increment` can bypass the owning process. The GenServer exists only to own the table; the clock is stored so both the hot path and queries can read it. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.

## The module with `init` missing

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe *time-windowed rate* collector backed by a named public
  ETS table.

  Events are bucketed by the wall-clock second at which they occur — the ETS
  key is `{name, second}` — so queries can answer "how many events in the last
  N seconds?". Recording is a lock-free `:ets.update_counter/4` on the public
  table and never routes through the owning GenServer.

  Time is injectable via the `:clock` option (a zero-arity function returning
  integer Unix seconds), which makes rates deterministic under test. The clock
  is stored in `:persistent_term` so both the hot path and queries can read it.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()
      Metrics.increment(:requests)         # => :ok
      Metrics.rate(:requests, 60)          # events in the last 60s
      Metrics.count(:requests)             # all-time total
  """

  use GenServer

  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
    * `:clock` — zero-arity function returning the current Unix time in integer
      seconds. Defaults to `fn -> System.system_time(:second) end`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Records `amount` events (default 1) for `name` at the current second.

  Atomically bumps the per-second bucket via `:ets.update_counter/4`. Returns
  `:ok`.
  """
  @spec increment(term(), non_neg_integer()) :: :ok
  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    second = now()
    key = {name, second}
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end

  @doc """
  Returns the number of events recorded for `name` within the last
  `window_seconds` — every bucket whose second is `> now - window_seconds`.
  """
  @spec rate(term(), pos_integer()) :: number()
  def rate(name, window_seconds) do
    cutoff = now() - window_seconds

    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}])
    |> Enum.sum()
  end

  @doc "Returns the all-time total number of events recorded for `name`."
  @spec count(term()) :: number()
  def count(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [:"$2"]}])
    |> Enum.sum()
  end

  @doc "Deletes every bucket for `name`."
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :_}, :_})
    :ok
  end

  @doc """
  Deletes all buckets (across every name) whose second is `<= now -
  retention_seconds`. Returns the number of buckets deleted.
  """
  @spec prune(non_neg_integer()) :: non_neg_integer()
  def prune(retention_seconds) do
    cutoff = now() - retention_seconds
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

  @doc "Returns a map of `%{name => all_time_total}`."
  @spec all() :: %{term() => non_neg_integer()}
  def all do
    :ets.foldl(
      fn {{name, _second}, amount}, acc ->
        Map.update(acc, name, amount, &(&1 + amount))
      end,
      %{},
      @table
    )
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp now, do: :persistent_term.get({@table, :clock}).()

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  def init(opts) do
    # TODO
  end
end
```

Give me only the complete implementation of `init` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
