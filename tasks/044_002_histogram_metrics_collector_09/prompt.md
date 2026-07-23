# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `init`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir module called `Metrics` that collects **latency/size distributions** using ETS for fast, concurrent-safe storage. This is a histogram collector (Prometheus-style), not a scalar counter/gauge collector.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration (defaulting to `__MODULE__`) and a `:buckets` option: a sorted ascending list of integer upper bounds. Default to `[10, 50, 100, 500, 1000]`.
- `Metrics.observe(name, value)` to record a single integer observation (e.g. a request latency in ms) for the histogram `name`, returning `:ok`. `value` must be a non-negative integer. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS using `:ets.update_counter`. Recording an observation atomically bumps the total count, the running sum, and the count for the matching bucket. A value `v` falls into the bucket of the smallest boundary `b` such that `v <= b`; a value larger than every boundary falls into the implicit `+Inf` bucket.
- `Metrics.get(name)` to return the current summary of the histogram as a map `%{count: c, sum: s, average: avg, buckets: %{...}}`, or `nil` if nothing has ever been observed for `name`. The `:buckets` map is **cumulative** ("less-than-or-equal"): each configured boundary maps to the number of observations `<= that boundary`, plus an `:infinity` key mapping to the total count. `:average` is `sum / count` as a float (the average of an empty histogram never arises because `get` returns `nil` when there are no observations).
- `Metrics.all()` to return a map of `%{name => total_count}` across every histogram.
- `Metrics.reset(name)` to erase all recorded data for `name` so that a subsequent `get(name)` returns `nil`.

The ETS table must be public and named so `observe` can bypass the owning process for maximum throughput. The GenServer exists only to own the table and to hold the bucket configuration. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.

## The module with `init` missing

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe histogram collector backed by a named public ETS table.

  Each observation atomically bumps three ETS counters — the total count, the
  running sum, and the matching bucket — all via `:ets.update_counter/4`, so
  the hot path never serialises through the owning GenServer. The GenServer
  exists only to own the table and hold the bucket configuration.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()
      Metrics.observe(:latency_ms, 42)      # => :ok
      Metrics.get(:latency_ms)
      # => %{count: 1, sum: 42, average: 42.0,
      #      buckets: %{10 => 0, 50 => 1, 100 => 1, 500 => 1, 1000 => 1, infinity: 1}}
  """

  use GenServer

  @table __MODULE__
  @default_buckets [10, 50, 100, 500, 1000]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
    * `:buckets` — sorted ascending list of integer upper bounds.
      Defaults to `#{inspect(@default_buckets)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Records a single non-negative integer observation for histogram `name`.

  Atomically increments the total count, the running sum and the count for the
  bucket that `value` falls into. Returns `:ok`.
  """
  @spec observe(term(), non_neg_integer()) :: :ok
  def observe(name, value) when is_integer(value) and value >= 0 do
    :ets.update_counter(@table, {name, :count}, {2, 1}, {{name, :count}, 0})
    :ets.update_counter(@table, {name, :sum}, {2, value}, {{name, :sum}, 0})
    u = bucket_for(value)
    :ets.update_counter(@table, {name, :bucket, u}, {2, 1}, {{name, :bucket, u}, 0})
    :ok
  end

  @doc """
  Returns the histogram summary for `name`, or `nil` if nothing was observed.

  The `:buckets` map is cumulative: each configured boundary maps to the number
  of observations `<=` that boundary, plus an `:infinity` key for the total.
  """
  @spec get(term()) :: map() | nil
  def get(name) do
    case :ets.lookup(@table, {name, :count}) do
      [] ->
        nil

      [{_, count}] ->
        sum = counter({name, :sum})
        boundaries = :persistent_term.get({@table, :buckets})

        {cumulative, _running} =
          Enum.reduce(boundaries, {%{}, 0}, fn b, {acc, running} ->
            running = running + counter({name, :bucket, b})
            {Map.put(acc, b, running), running}
          end)

        buckets = Map.put(cumulative, :infinity, count)
        %{count: count, sum: sum, average: sum / count, buckets: buckets}
    end
  end

  @doc """
  Returns a map of `%{name => total_count}` across every histogram.
  """
  @spec all() :: %{term() => non_neg_integer()}
  def all do
    :ets.foldl(
      fn
        {{name, :count}, v}, acc -> Map.put(acc, name, v)
        _other, acc -> acc
      end,
      %{},
      @table
    )
  end

  @doc """
  Erases all recorded data for `name`, so a later `get/1` returns `nil`.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :count}, :_})
    :ets.match_delete(@table, {{name, :sum}, :_})
    :ets.match_delete(@table, {{name, :bucket, :_}, :_})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp bucket_for(value) do
    boundaries = :persistent_term.get({@table, :buckets})
    Enum.find(boundaries, :inf, fn b -> value <= b end)
  end

  defp counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, v}] -> v
      [] -> 0
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  def init(opts) do
    # TODO
  end
end
```

Output only `init` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
