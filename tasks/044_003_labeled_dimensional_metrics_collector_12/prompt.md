# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Metrics` that collects **dimensional (labeled) metrics** using ETS for fast, concurrent-safe storage. Unlike a flat counter collector, each metric is identified by a name *plus a set of labels* (a map, e.g. `%{method: "GET", status: 200}`), so the same metric name can carry many independent label combinations — exactly like Prometheus time series.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It accepts a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, labels \\ %{}, amount \\ 1)` to atomically increment the counter for a specific `{name, labels}` series by `amount` (a non-negative integer), creating the series (starting from `0`) if it does not exist yet. Use `:ets.update_counter` on the hot path — increments must NOT serialize through the GenServer. Two labels maps with the same key/value pairs in a different order (`%{a: 1, b: 2}` vs `%{b: 2, a: 1}`) refer to the *same* series. Support the natural call shapes: `increment(name)`, `increment(name, labels)`, `increment(name, amount)`, and `increment(name, labels, amount)`. A negative `amount` must raise a `FunctionClauseError` (in both the `increment(name, amount)` and `increment(name, labels, amount)` forms) without creating or touching any series; `0` is a valid amount at the non-negative boundary that leaves the value unchanged (recording the series at `0` if it was new).
- `Metrics.gauge(name, value)` and `Metrics.gauge(name, labels, value)` to set the exact value of a series, overwriting the previous value.
- `Metrics.get(name, labels)` to return the current value of a specific series, or `nil` if that exact series does not exist.
- `Metrics.get(name)` to return the **aggregate** across all label combinations for that name (the sum of every series' value), or `nil` if the name has no series at all.
- `Metrics.series(name)` to return a list of `%{labels: labels_map, value: value}` — one entry per label combination recorded under `name` (in any order), or `[]` if the name has no series.
- `Metrics.reset(name, labels)` to set one specific series back to `0`, and `Metrics.reset(name)` to set *every* series under `name` back to `0` (leaving series recorded under other names untouched).
- `Metrics.all()` to return a map keyed by `{name, labels_map}` mapping to each series' value.

Throughout, the `labels_map` you hand back (from `series/1` and `all/0`) must be a plain map equal to what was passed in regardless of the original key order. The ETS table must be public and named so `increment` can bypass the owning process. The GenServer exists only to own the table. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.

## The module with `start_link` missing

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe *dimensional* metrics collector backed by a named public
  ETS table.

  Every metric is identified by a name plus a set of labels (a map). A series
  is keyed by `{name, canonical_labels}` where `canonical_labels` is the labels
  map sorted into a stable list, so label order never matters. Counter
  increments use `:ets.update_counter/4` directly against the public table and
  never serialise through the owning GenServer.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()
      Metrics.increment(:requests, %{method: "GET"})   # => :ok
      Metrics.increment(:requests, %{method: "POST"}, 3)
      Metrics.get(:requests, %{method: "GET"})         # => 1
      Metrics.get(:requests)                           # => 4 (aggregate)
      Metrics.series(:requests)
      # => [%{labels: %{method: "GET"}, value: 1},
      #     %{labels: %{method: "POST"}, value: 3}]
  """

  use GenServer

  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    # TODO
  end

  @doc "Increments the `{name, labels}` counter by `amount` (default 1)."
  @spec increment(term()) :: :ok
  def increment(name), do: increment(name, %{}, 1)

  @spec increment(term(), map() | non_neg_integer()) :: :ok
  def increment(name, labels) when is_map(labels), do: increment(name, labels, 1)
  def increment(name, amount) when is_integer(amount), do: increment(name, %{}, amount)

  @spec increment(term(), map(), non_neg_integer()) :: :ok
  def increment(name, labels, amount)
      when is_map(labels) and is_integer(amount) and amount >= 0 do
    key = key(name, labels)
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end

  @doc "Sets the `{name, %{}}` gauge to exactly `value`."
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value), do: gauge(name, %{}, value)

  @doc "Sets the `{name, labels}` gauge to exactly `value`."
  @spec gauge(term(), map(), number()) :: :ok
  def gauge(name, labels, value) when is_map(labels) do
    :ets.insert(@table, {key(name, labels), value})
    :ok
  end

  @doc "Returns the value of a specific series, or `nil` if it does not exist."
  @spec get(term(), map()) :: number() | nil
  def get(name, labels) when is_map(labels) do
    case :ets.lookup(@table, key(name, labels)) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Returns the aggregate (sum) across every series under `name`, or `nil` if the
  name has no series.
  """
  @spec get(term()) :: number() | nil
  def get(name) do
    case :ets.select(@table, [{{{name, :"$1"}, :"$2"}, [], [:"$2"]}]) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  @doc "Returns one `%{labels: map, value: value}` entry per series under `name`."
  @spec series(term()) :: [%{labels: map(), value: number()}]
  def series(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {norm, value} -> %{labels: Map.new(norm), value: value} end)
  end

  @doc "Resets one specific series to `0`."
  @spec reset(term(), map()) :: :ok
  def reset(name, labels) when is_map(labels) do
    :ets.insert(@table, {key(name, labels), 0})
    :ok
  end

  @doc "Resets every series under `name` to `0`."
  @spec reset(term()) :: :ok
  def reset(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :_}, [], [:"$1"]}])
    |> Enum.each(fn norm -> :ets.insert(@table, {{name, norm}, 0}) end)

    :ok
  end

  @doc "Returns all series as a map keyed by `{name, labels_map}`."
  @spec all() :: %{{term(), map()} => number()}
  def all do
    :ets.foldl(
      fn {{name, norm}, value}, acc -> Map.put(acc, {name, Map.new(norm)}, value) end,
      %{},
      @table
    )
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # Canonicalise labels to a sorted list so key/value order is irrelevant.
  defp key(name, labels), do: {name, Enum.sort(labels)}

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end
end
```

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
