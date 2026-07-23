# Fill in one @spec

Below: a working module where the `@spec` for
`get/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `get/2` missing

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
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
