defmodule Metrics do
  @moduledoc """
  A Prometheus-style histogram collector backed by ETS.

  `Metrics` records distributions of integer observations (latencies, payload
  sizes, …) into a fixed set of buckets. The backing ETS table is `:public` and
  `:named_table`, so `observe/2` — the hot path — writes directly to ETS with
  `:ets.update_counter/4` and never serializes through the owning process.

  The GenServer started by `start_link/1` exists solely to own the table (so it
  is garbage collected with the supervision tree) and to hold the bucket
  configuration.

  ## Layout

  Each histogram `name` owns the following keys in the table:

    * `{name, :count}` — total number of observations
    * `{name, :sum}` — running sum of all observed values
    * `{name, {:bucket, index}}` — number of observations that landed exactly in
      the bucket at `index`, where `index` ranges over the configured boundaries
      plus one trailing slot for the implicit `+Inf` bucket

  Bucket counts are stored non-cumulatively and summed on read by `get/1`, which
  keeps the write path to a single atomic `:ets.update_counter/4` call.

  ## Example

      iex> {:ok, _pid} = Metrics.start_link(buckets: [10, 100])
      iex> Metrics.observe(:http_request, 5)
      iex> Metrics.observe(:http_request, 250)
      iex> Metrics.get(:http_request)
      %{
        count: 2,
        sum: 255,
        average: 127.5,
        buckets: %{10 => 1, 100 => 1, infinity: 2}
      }
  """

  use GenServer

  @table __MODULE__.Table
  @config_key :__config__
  @default_buckets [10, 50, 100, 500, 1000]

  @type name :: term()
  @type summary :: %{
          count: pos_integer(),
          sum: non_neg_integer(),
          average: float(),
          buckets: %{optional(pos_integer()) => non_neg_integer(), infinity: non_neg_integer()}
        }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the histogram collector and creates the backing ETS table.

  ## Options

    * `:name` — the name the GenServer registers under. Defaults to `#{inspect(__MODULE__)}`.
    * `:buckets` — a list of integer upper bounds, sorted ascending, with no
      duplicates. Defaults to `#{inspect(@default_buckets)}`.

  Raises `ArgumentError` if `:buckets` is not a non-empty, strictly ascending
  list of integers.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    buckets = opts |> Keyword.get(:buckets, @default_buckets) |> validate_buckets!()
    GenServer.start_link(__MODULE__, buckets, name: name)
  end

  @doc """
  Records a single observation of `value` for the histogram `name`.

  `value` must be a non-negative integer. The call bumps the total count, the
  running sum and the matching bucket in one atomic `:ets.update_counter/4`
  operation, bypassing the owning process entirely.

  A value `v` falls into the bucket of the smallest configured boundary `b` for
  which `v <= b`; a value greater than every boundary lands in the implicit
  `+Inf` bucket.

  Returns `:ok`. Raises `ArgumentError` if the collector has not been started.
  """
  @spec observe(name(), non_neg_integer()) :: :ok
  def observe(name, value) when is_integer(value) and value >= 0 do
    index = bucket_index(buckets(), value, 0)

    ensure_keys(name, index)

    :ets.update_counter(@table, {name, :count}, {2, 1})
    :ets.update_counter(@table, {name, :sum}, {2, value})
    :ets.update_counter(@table, {name, {:bucket, index}}, {2, 1})

    :ok
  end

  @doc """
  Returns the current summary of the histogram `name`, or `nil` if nothing has
  ever been observed for it.

  The `:buckets` map is cumulative: each configured boundary maps to the number
  of observations less than or equal to it, and the `:infinity` key maps to the
  total number of observations. `:average` is `sum / count` as a float.
  """
  @spec get(name()) :: summary() | nil
  def get(name) do
    case :ets.lookup(@table, {name, :count}) do
      [] ->
        nil

      [{_key, count}] ->
        [{_sum_key, sum}] = :ets.lookup(@table, {name, :sum})

        %{
          count: count,
          sum: sum,
          average: sum / count,
          buckets: cumulative_buckets(name, buckets())
        }
    end
  end

  @doc """
  Returns a map of `%{name => total_count}` for every histogram that has
  recorded at least one observation.
  """
  @spec all() :: %{optional(name()) => non_neg_integer()}
  def all do
    @table
    |> :ets.match({{:"$1", :count}, :"$2"})
    |> Map.new(fn [name, count] -> {name, count} end)
  end

  @doc """
  Erases every observation recorded for the histogram `name`, so that a
  subsequent `get/1` returns `nil`. Always returns `:ok`, even for an unknown
  name.
  """
  @spec reset(name()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :count}, :_})
    :ets.match_delete(@table, {{name, :sum}, :_})
    :ets.match_delete(@table, {{name, {:bucket, :_}}, :_})
    :ok
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  def init(buckets) do
    table =
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true,
        decentralized_counters: true
      ])

    :ets.insert(table, {@config_key, buckets})
    {:ok, %{table: table, buckets: buckets}}
  end

  @impl GenServer
  def handle_call(:buckets, _from, state) do
    {:reply, state.buckets, state}
  end

  # ── Internals ─────────────────────────────────────────────────────────────

  @spec buckets() :: [pos_integer()]
  defp buckets do
    case :ets.lookup(@table, @config_key) do
      [{@config_key, buckets}] ->
        buckets

      [] ->
        raise ArgumentError, "#{inspect(__MODULE__)} is not started"
    end
  end

  # Index of the first boundary that `value` fits under; `length(buckets)` for
  # the implicit `+Inf` bucket.
  @spec bucket_index([pos_integer()], non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp bucket_index([], _value, index), do: index
  defp bucket_index([bound | _rest], value, index) when value <= bound, do: index
  defp bucket_index([_bound | rest], value, index), do: bucket_index(rest, value, index + 1)

  # Insert-if-absent so `update_counter/4` never raises on a fresh histogram.
  @spec ensure_keys(name(), non_neg_integer()) :: :ok
  defp ensure_keys(name, index) do
    :ets.insert_new(@table, {{name, :count}, 0})
    :ets.insert_new(@table, {{name, :sum}, 0})
    :ets.insert_new(@table, {{name, {:bucket, index}}, 0})
    :ok
  end

  @spec cumulative_buckets(name(), [pos_integer()]) :: %{
          optional(pos_integer()) => non_neg_integer(),
          infinity: non_neg_integer()
        }
  defp cumulative_buckets(name, buckets) do
    {map, running} =
      buckets
      |> Enum.with_index()
      |> Enum.reduce({%{}, 0}, fn {bound, index}, {acc, running} ->
        running = running + bucket_count(name, index)
        {Map.put(acc, bound, running), running}
      end)

    inf = running + bucket_count(name, length(buckets))
    Map.put(map, :infinity, inf)
  end

  @spec bucket_count(name(), non_neg_integer()) :: non_neg_integer()
  defp bucket_count(name, index) do
    case :ets.lookup(@table, {name, {:bucket, index}}) do
      [{_key, count}] -> count
      [] -> 0
    end
  end

  @spec validate_buckets!(term()) :: [pos_integer()]
  defp validate_buckets!(buckets) when is_list(buckets) and buckets != [] do
    unless Enum.all?(buckets, &is_integer/1) do
      raise ArgumentError, ":buckets must be a list of integers, got: #{inspect(buckets)}"
    end

    unless strictly_ascending?(buckets) do
      raise ArgumentError,
            ":buckets must be sorted ascending with no duplicates, got: #{inspect(buckets)}"
    end

    buckets
  end

  defp validate_buckets!(other) do
    raise ArgumentError, ":buckets must be a non-empty list of integers, got: #{inspect(other)}"
  end

  @spec strictly_ascending?([integer()]) :: boolean()
  defp strictly_ascending?([_single]), do: true
  defp strictly_ascending?([a, b | rest]) when a < b, do: strictly_ascending?([b | rest])
  defp strictly_ascending?(_other), do: false
end