defmodule ReconcilerServer do
  @moduledoc """
  A `GenServer` that incrementally accumulates records from two sides — a
  "left" side and a "right" side — and reconciles the current accumulated
  state on demand.

  Records arrive over time via `put_left/2` and `put_right/2`, and may be
  removed via `delete_left/2` and `delete_right/2`. Each record is a map, and
  records are matched across the two sides by a shared composite key built from
  a configured list of key fields.

  Calling `reconcile/1` produces a structured diff of the state at that moment:
  matched records (with a field-level difference map), records present only on
  the left, and records present only on the right.

  The server uses only the Elixir/OTP standard library.
  """

  use GenServer

  @typedoc "A single record, represented as a map."
  @type record :: map()

  @typedoc "The composite key extracted from a record's key fields."
  @type composite_key :: tuple()

  @typedoc "A field-level difference map for a matched pair of records."
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @typedoc "The result of a reconciliation."
  @type reconciliation :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  # --- Client API -----------------------------------------------------------

  @doc """
  Starts the reconciliation server.

  `opts` is a keyword list supporting:

    * `:key_fields` (required) — a non-empty list of atoms forming the
      composite key. Raises `ArgumentError` if missing, empty, or not a list of
      atoms.
    * `:compare_fields` (optional) — a list of atoms specifying which fields to
      diff on matched records. If omitted or `nil`, all fields except the key
      fields are compared.
    * `:name` (optional) — if given, the server is registered under this name.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields = Keyword.get(opts, :key_fields)
    validate_key_fields!(key_fields)

    compare_fields = Keyword.get(opts, :compare_fields)
    validate_compare_fields!(compare_fields)

    init_arg = %{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, init_arg, name: name)
      :error -> GenServer.start_link(__MODULE__, init_arg)
    end
  end

  @doc """
  Stores `record` on the left side. If a left record with the same composite
  key already exists, it is replaced (last write wins). Returns `:ok`.
  """
  @spec put_left(GenServer.server(), record()) :: :ok
  def put_left(server, record) when is_map(record) do
    GenServer.call(server, {:put, :left, record})
  end

  @doc """
  Stores `record` on the right side. If a right record with the same composite
  key already exists, it is replaced (last write wins). Returns `:ok`.
  """
  @spec put_right(GenServer.server(), record()) :: :ok
  def put_right(server, record) when is_map(record) do
    GenServer.call(server, {:put, :right, record})
  end

  @doc """
  Removes the left record whose composite key matches that of `record`. Only
  the key fields of `record` are used to locate it. No-op if absent. Returns
  `:ok`.
  """
  @spec delete_left(GenServer.server(), record()) :: :ok
  def delete_left(server, record) when is_map(record) do
    GenServer.call(server, {:delete, :left, record})
  end

  @doc """
  Removes the right record whose composite key matches that of `record`. Only
  the key fields of `record` are used to locate it. No-op if absent. Returns
  `:ok`.
  """
  @spec delete_right(GenServer.server(), record()) :: :ok
  def delete_right(server, record) when is_map(record) do
    GenServer.call(server, {:delete, :right, record})
  end

  @doc """
  Computes and returns the reconciliation of the current accumulated state as a
  map with `:matched`, `:only_in_left`, and `:only_in_right` keys.
  """
  @spec reconcile(GenServer.server()) :: reconciliation()
  def reconcile(server) do
    GenServer.call(server, :reconcile)
  end

  # --- Server callbacks -----------------------------------------------------

  @impl true
  def init(%{key_fields: key_fields, compare_fields: compare_fields}) do
    state = %{
      key_fields: key_fields,
      compare_fields: compare_fields,
      left: %{},
      right: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:put, side, record}, _from, state) do
    %{key_fields: key_fields} = state
    key = composite_key(record, key_fields)
    updated = Map.put(Map.fetch!(state, side), key, record)
    {:reply, :ok, Map.put(state, side, updated)}
  end

  def handle_call({:delete, side, record}, _from, state) do
    %{key_fields: key_fields} = state
    key = composite_key(record, key_fields)
    updated = Map.delete(Map.fetch!(state, side), key)
    {:reply, :ok, Map.put(state, side, updated)}
  end

  def handle_call(:reconcile, _from, state) do
    {:reply, do_reconcile(state), state}
  end

  # --- Internal helpers -----------------------------------------------------

  @spec validate_key_fields!(term()) :: :ok
  defp validate_key_fields!(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, &is_atom/1) do
      :ok
    else
      raise ArgumentError, ":key_fields must be a non-empty list of atoms"
    end
  end

  defp validate_key_fields!(_fields) do
    raise ArgumentError, ":key_fields must be a non-empty list of atoms"
  end

  @spec validate_compare_fields!(term()) :: :ok
  defp validate_compare_fields!(nil), do: :ok

  defp validate_compare_fields!(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      :ok
    else
      raise ArgumentError, ":compare_fields must be a list of atoms or nil"
    end
  end

  defp validate_compare_fields!(_fields) do
    raise ArgumentError, ":compare_fields must be a list of atoms or nil"
  end

  @spec composite_key(record(), [atom()]) :: composite_key()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(fn field -> Map.get(record, field) end)
    |> List.to_tuple()
  end

  @spec do_reconcile(map()) :: reconciliation()
  defp do_reconcile(state) do
    %{
      left: left,
      right: right,
      key_fields: key_fields,
      compare_fields: compare_fields
    } = state

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
          differences: compute_differences(left_record, right_record, compare_fields, key_fields)
        }
      end)

    %{
      matched: matched,
      only_in_left: Enum.map(only_left_keys, &Map.fetch!(left, &1)),
      only_in_right: Enum.map(only_right_keys, &Map.fetch!(right, &1))
    }
  end

  @spec compute_differences(record(), record(), [atom()] | nil, [atom()]) :: diff_map()
  defp compute_differences(left_record, right_record, compare_fields, key_fields) do
    fields = fields_to_compare(left_record, right_record, compare_fields, key_fields)

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

  @spec fields_to_compare(record(), record(), [atom()] | nil, [atom()]) :: [atom()]
  defp fields_to_compare(_left_record, _right_record, compare_fields, _key_fields)
       when is_list(compare_fields) do
    compare_fields
  end

  defp fields_to_compare(left_record, right_record, _compare_fields, key_fields) do
    default_compare_fields(left_record, right_record, key_fields)
  end

  @spec default_compare_fields(record(), record(), [atom()]) :: [atom()]
  defp default_compare_fields(left_record, right_record, key_fields) do
    key_set = MapSet.new(key_fields)

    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(fn field -> MapSet.member?(key_set, field) end)
  end
end
