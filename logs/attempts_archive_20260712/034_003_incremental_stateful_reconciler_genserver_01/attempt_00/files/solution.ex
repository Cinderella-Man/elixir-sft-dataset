defmodule Reconciler do
  @moduledoc """
  An incremental, stateful reconciler for two sides of records.

  `Reconciler` is a `GenServer` that accumulates records on a "left" side and a
  "right" side, one at a time, and computes a reconciliation on demand over
  whatever has been accumulated so far.

  Records are plain maps. Two records "match" when all of the configured
  `:key_fields` compare equal (using `==`). For matched records, a set of
  `:compare_fields` is diffed field by field; when `:compare_fields` is omitted
  the comparison uses every field except the key fields (across both records).

  The reconciliation result classifies composite keys into three buckets:

    * `:matched` — keys present on both sides, with a per-field difference map;
    * `:only_in_left` — keys present only on the left side;
    * `:only_in_right` — keys present only on the right side.

  Reconciling never consumes state: `reconcile/1` may be called repeatedly and
  always reflects every `put_left/2` and `put_right/2` performed so far.
  """

  use GenServer

  @typedoc "A record is an arbitrary map of fields to values."
  @type record :: map()

  @typedoc "A composite key: the tuple of key-field values, in `:key_fields` order."
  @type key :: tuple()

  @typedoc "A per-field difference: `%{field => %{left: val, right: val}}`."
  @type diff_map :: %{optional(atom()) => %{left: any(), right: any()}}

  @typedoc "A single matched entry, including both full records and their diff."
  @type matched_entry :: %{left: record(), right: record(), differences: diff_map()}

  @typedoc "The full reconciliation result."
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  # Internal server state.
  defstruct key_fields: [], compare_fields: nil, left: %{}, right: %{}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the reconciler server.

  `opts` is a keyword list supporting:

    * `:key_fields` (required) — a list of atoms forming the composite key used
      to match records across the two sides. Raises `ArgumentError` if missing.
    * `:compare_fields` (optional) — a list of atoms specifying which fields to
      diff on matched records. When omitted or `nil`, all fields except the key
      fields are compared.

  Any remaining options (such as `:name`) are forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields =
      case Keyword.fetch(opts, :key_fields) do
        {:ok, fields} when is_list(fields) ->
          fields

        {:ok, _other} ->
          raise ArgumentError, ":key_fields must be a list of atoms"

        :error ->
          raise ArgumentError, ":key_fields option is required"
      end

    compare_fields = Keyword.get(opts, :compare_fields)

    gen_opts = Keyword.take(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    init_arg = %{key_fields: key_fields, compare_fields: compare_fields}

    GenServer.start_link(__MODULE__, init_arg, gen_opts)
  end

  @doc """
  Adds `record` (a map) to the left side.

  If a record with the same composite key was already put on the left side, it
  is replaced (last write wins). Always returns `:ok`.
  """
  @spec put_left(GenServer.server(), record()) :: :ok
  def put_left(server, record) when is_map(record) do
    GenServer.call(server, {:put, :left, record})
  end

  @doc """
  Adds `record` (a map) to the right side.

  If a record with the same composite key was already put on the right side, it
  is replaced (last write wins). Always returns `:ok`.
  """
  @spec put_right(GenServer.server(), record()) :: :ok
  def put_right(server, record) when is_map(record) do
    GenServer.call(server, {:put, :right, record})
  end

  @doc """
  Computes and returns the reconciliation over the currently accumulated state.

  Returns a map with `:matched`, `:only_in_left`, and `:only_in_right` keys.
  This call does not consume or clear state and may be called repeatedly. The
  order of results within each bucket is unspecified.
  """
  @spec reconcile(GenServer.server()) :: result()
  def reconcile(server) do
    GenServer.call(server, :reconcile)
  end

  @doc """
  Clears both sides, leaving the server empty.

  After a reset, `reconcile/1` returns
  `%{matched: [], only_in_left: [], only_in_right: []}`. Always returns `:ok`.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(%{key_fields: [atom()], compare_fields: [atom()] | nil}) :: {:ok, %__MODULE__{}}
  def init(%{key_fields: key_fields, compare_fields: compare_fields}) do
    state = %__MODULE__{
      key_fields: key_fields,
      compare_fields: compare_fields,
      left: %{},
      right: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:put, side, record}, _from, state) do
    key = build_key(record, state.key_fields)
    side_map = Map.put(Map.fetch!(state, side), key, record)
    {:reply, :ok, Map.put(state, side, side_map)}
  end

  def handle_call(:reconcile, _from, state) do
    {:reply, compute(state), state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | left: %{}, right: %{}}}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # Builds the composite key tuple for a record, missing fields becoming nil.
  @spec build_key(record(), [atom()]) :: key()
  defp build_key(record, key_fields) do
    key_fields
    |> Enum.map(fn field -> Map.get(record, field) end)
    |> List.to_tuple()
  end

  # Computes the full reconciliation result from accumulated state.
  @spec compute(%__MODULE__{}) :: result()
  defp compute(%__MODULE__{left: left, right: right} = state) do
    left_keys = MapSet.new(Map.keys(left))
    right_keys = MapSet.new(Map.keys(right))

    matched_keys = MapSet.intersection(left_keys, right_keys)
    only_left_keys = MapSet.difference(left_keys, right_keys)
    only_right_keys = MapSet.difference(right_keys, left_keys)

    matched =
      Enum.map(matched_keys, fn key ->
        left_record = Map.fetch!(left, key)
        right_record = Map.fetch!(right, key)

        %{
          left: left_record,
          right: right_record,
          differences: diff(left_record, right_record, state)
        }
      end)

    only_in_left = Enum.map(only_left_keys, fn key -> Map.fetch!(left, key) end)
    only_in_right = Enum.map(only_right_keys, fn key -> Map.fetch!(right, key) end)

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
  end

  # Diffs a matched pair of records over the configured compare fields.
  @spec diff(record(), record(), %__MODULE__{}) :: diff_map()
  defp diff(left_record, right_record, state) do
    fields = compare_fields(left_record, right_record, state)

    Enum.reduce(fields, %{}, fn field, acc ->
      left_val = Map.get(left_record, field)
      right_val = Map.get(right_record, field)

      if left_val == right_val do
        acc
      else
        Map.put(acc, field, %{left: left_val, right: right_val})
      end
    end)
  end

  # Determines which fields to compare for a matched pair.
  @spec compare_fields(record(), record(), %__MODULE__{}) :: [atom()]
  defp compare_fields(_left_record, _right_record, %__MODULE__{compare_fields: fields})
       when is_list(fields) do
    fields
  end

  defp compare_fields(left_record, right_record, %__MODULE__{key_fields: key_fields}) do
    key_set = MapSet.new(key_fields)

    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(fn field -> MapSet.member?(key_set, field) end)
  end
end
