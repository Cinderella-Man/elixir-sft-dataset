defmodule StreamingReconciler do
  @moduledoc """
  A GenServer that incrementally reconciles two streams of records.

  Records arrive one at a time, tagged as coming from the left side or the
  right side, rather than as two complete lists provided up front. At any
  point the current reconciliation can be queried via `snapshot/1`.

  Two records are considered a match when all of the configured `:key_fields`
  are equal. Matched records are diffed on the configured `:compare_fields`
  (or, when none are configured, on every field present in either record
  except the key fields).

  Reconciliation always reflects whatever has been ingested so far: a key that
  appears only on the left in one snapshot becomes matched as soon as a right
  record with the same key is added. Within a single side, re-ingesting the
  same key replaces the previous record for that side.
  """

  use GenServer

  @typedoc "A single record; a map keyed by field name."
  @type record :: map()

  @typedoc "A composite key: the tuple of values for the configured key fields."
  @type key :: tuple()

  @typedoc "Per-field difference map for a matched pair."
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @typedoc "The internal server state."
  @type state :: %{
          key_fields: [atom()],
          compare_fields: [atom()] | nil,
          left: %{optional(key()) => record()},
          right: %{optional(key()) => record()}
        }

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the reconciler server.

  Options:

    * `:key_fields` (required) — list of atoms forming the composite key used
      to match a left record against a right record.
    * `:compare_fields` (optional) — list of atoms specifying which fields to
      diff on matched records. When omitted or `nil`, all fields present in
      either matched record except the key fields are compared.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    key_fields = Keyword.fetch!(opts, :key_fields)
    compare_fields = Keyword.get(opts, :compare_fields)
    GenServer.start_link(__MODULE__, {key_fields, compare_fields})
  end

  @doc """
  Ingests one record into the left side. Returns `:ok`.
  """
  @spec add_left(GenServer.server(), record()) :: :ok
  def add_left(pid, record) do
    GenServer.call(pid, {:add, :left, record})
  end

  @doc """
  Ingests one record into the right side. Returns `:ok`.
  """
  @spec add_right(GenServer.server(), record()) :: :ok
  def add_right(pid, record) do
    GenServer.call(pid, {:add, :right, record})
  end

  @doc """
  Returns the current reconciliation as a map with the keys `:matched`,
  `:only_in_left`, and `:only_in_right`.

    * `:matched` — a list of `%{left: record, right: record,
      differences: diff_map}` entries for keys present on both sides.
    * `:only_in_left` — the left records whose key has not yet been seen on
      the right side.
    * `:only_in_right` — the right records whose key has not yet been seen on
      the left side.

  The order of the lists is unspecified.
  """
  @spec snapshot(GenServer.server()) :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }
  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  end

  @doc """
  Discards all ingested records on both sides, returning the server to an
  empty state. Returns `:ok`.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(pid) do
    GenServer.call(pid, :reset)
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init({key_fields, compare_fields}) do
    state = %{
      key_fields: key_fields,
      compare_fields: compare_fields,
      left: %{},
      right: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add, :left, record}, _from, state) do
    {:reply, :ok, put_record(state, :left, record)}
  end

  def handle_call({:add, :right, record}, _from, state) do
    {:reply, :ok, put_record(state, :right, record)}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | left: %{}, right: %{}}}
  end

  # ------------------------------------------------------------------
  # Internal helpers
  # ------------------------------------------------------------------

  @spec put_record(state(), :left | :right, record()) :: state()
  defp put_record(state, side, record) do
    key = record_key(record, state.key_fields)
    Map.update!(state, side, &Map.put(&1, key, record))
  end

  @spec record_key(record(), [atom()]) :: key()
  defp record_key(record, key_fields) do
    key_fields
    |> Enum.map(fn field -> Map.get(record, field) end)
    |> List.to_tuple()
  end

  @spec build_snapshot(state()) :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }
  defp build_snapshot(state) do
    %{left: left, right: right} = state
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
          differences: differences(left_record, right_record, state)
        }
      end)

    %{
      matched: matched,
      only_in_left: Enum.map(only_left_keys, &Map.fetch!(left, &1)),
      only_in_right: Enum.map(only_right_keys, &Map.fetch!(right, &1))
    }
  end

  @spec differences(record(), record(), state()) :: diff_map()
  defp differences(left_record, right_record, state) do
    fields = compare_fields(left_record, right_record, state)

    Enum.reduce(fields, %{}, fn field, acc ->
      left_value = Map.get(left_record, field)
      right_value = Map.get(right_record, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  @spec compare_fields(record(), record(), state()) :: [atom()]
  defp compare_fields(_left_record, _right_record, %{compare_fields: fields})
       when is_list(fields) do
    fields
  end

  defp compare_fields(left_record, right_record, %{key_fields: key_fields}) do
    key_set = MapSet.new(key_fields)

    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end
end
