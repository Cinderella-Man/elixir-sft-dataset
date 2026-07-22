Implement the private `bucket_for/1` function. Given a non-negative integer
`value`, it must determine which histogram bucket the value belongs to. Read the
configured, ascending list of integer boundaries from persistent term storage
under the key `{@table, :buckets}`. Return the smallest boundary `b` such that
`value <= b`. If `value` is larger than every boundary, it falls into the
implicit `+Inf` bucket, so return the atom `:inf` instead. This value is used as
part of the ETS counter key for the matching bucket in `observe/2`.

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
    # TODO
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

  @impl GenServer
  def init(opts) do
    buckets = Keyword.get(opts, :buckets, @default_buckets)
    :persistent_term.put({@table, :buckets}, buckets)

    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{buckets: buckets}}
  end
end
```