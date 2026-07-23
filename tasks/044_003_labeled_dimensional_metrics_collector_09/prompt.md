# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `init`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Hey — I need you to write a module for us called `Metrics`, and I want to be specific about what it has to do because the flat counter collector we have today isn't cutting it.

The idea is **dimensional (labeled) metrics**, backed by ETS so storage is fast and concurrent-safe. Instead of a metric being identified by a name alone, each one is identified by a name *plus a set of labels* — a map, e.g. `%{method: "GET", status: 200}` — so a single metric name can carry many independent label combinations, exactly like Prometheus time series.

Here's the public API I'm asking for:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, labels \\ %{}, amount \\ 1)` to atomically increment the counter for a specific `{name, labels}` series by `amount` (a non-negative integer), creating the series (starting from `0`) if it doesn't exist yet. I want `:ets.update_counter` on the hot path — increments must NOT serialize through the GenServer. Two labels maps with the same key/value pairs in a different order (`%{a: 1, b: 2}` vs `%{b: 2, a: 1}`) have to refer to the *same* series. Please support the natural call shapes: `increment(name)`, `increment(name, labels)`, `increment(name, amount)`, and `increment(name, labels, amount)`. A negative `amount` must raise a `FunctionClauseError` (in both the `increment(name, amount)` and the `increment(name, labels, amount)` forms) without creating or touching any series; `0` is a valid amount at the non-negative boundary and leaves the value unchanged (recording the series at `0` if it was new).
- `Metrics.gauge(name, value)` and `Metrics.gauge(name, labels, value)` to set the exact value of a series, overwriting whatever was there before.
- `Metrics.get(name, labels)` to give me back the current value of that specific series, or `nil` if that exact series doesn't exist.
- `Metrics.get(name)` to give me the **aggregate** across all label combinations for that name — the sum of every series' value — or `nil` if the name has no series at all.
- `Metrics.series(name)` to return a list of `%{labels: labels_map, value: value}`, one entry per label combination recorded under `name` (order doesn't matter), or `[]` if the name has no series.
- `Metrics.reset(name, labels)` to set one specific series back to `0`, and `Metrics.reset(name)` to set *every* series under `name` back to `0`, leaving series recorded under other names untouched.
- `Metrics.all()` to return a map keyed by `{name, labels_map}` mapping to each series' value.

A couple of things that apply throughout: the `labels_map` you hand back (from `series/1` and `all/0`) has to be a plain map equal to what was passed in, regardless of the original key order. The ETS table needs to be public and named so `increment` can bypass the owning process — the GenServer exists only to own the table. Stick to OTP/stdlib, no external dependencies. Send me the complete implementation in a single file.

## The module with `init` missing

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

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
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

  def init(_opts) do
    # TODO
  end
end
```

Output only `init` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
