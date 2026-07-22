defmodule StreamReconciler do
  @moduledoc """
  A `GenServer` that reconciles two record streams incrementally.

  Records arrive one at a time from either the left or the right feed, possibly
  interleaved and out of order. Each record is keyed by a composite key built
  from the configured `:key_fields`. When a record arrives and no counterpart is
  waiting on the other side, it is parked as *pending*. When its counterpart
  eventually arrives, the pair is completed: a matched entry is returned from the
  push and also appended to an internal buffer that can be drained later with
  `take_matches/1`.

  A completed pair produces an entry of the shape:

      %{
        key: %{key_field => value},
        left: left_record,
        right: right_record,
        differences: %{field => %{left: left_value, right: right_value}}
      }

  Differences are computed over `:compare_fields` when given, otherwise over
  every field present in either record of the pair minus the key fields. A field
  missing from a record is treated as `nil`.

  ## Example

      {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
      :pending = StreamReconciler.push_left(pid, %{id: 1, amount: 10})
      {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, amount: 12})
      entry.differences
      #=> %{amount: %{left: 10, right: 12}}
      [^entry] = StreamReconciler.take_matches(pid)
      [] = StreamReconciler.take_matches(pid)

  """

  use GenServer

  @typedoc "A record from either stream."
  @type record :: map()

  @typedoc "The composite key of a record: its values at the key fields, in order."
  @type key :: tuple()

  @typedoc "A completed match entry."
  @type entry :: %{
          key: map(),
          left: record(),
          right: record(),
          differences: %{optional(atom()) => %{left: term(), right: term()}}
        }

  defmodule State do
    @moduledoc false

    defstruct key_fields: [],
              compare_fields: nil,
              pending_left: %{},
              pending_right: %{},
              matches: []
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the reconciler.

  ## Options

    * `:key_fields` (required) — a non-empty list of atoms forming the composite
      key. Raises `ArgumentError` if missing or not a non-empty list of atoms.
    * `:compare_fields` (optional) — a list of atoms to diff on a completed pair.
      When omitted or `nil`, every field present in either record of the pair is
      compared, minus the key fields.
    * `:name` (optional) — a name to register the server under.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields = validate_key_fields(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields(Keyword.get(opts, :compare_fields))

    state = %State{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, state, name: name)
      :error -> GenServer.start_link(__MODULE__, state)
    end
  end

  @doc """
  Feeds one record from the left stream.

  Returns `{:matched, entry}` if a pending right record with the same key was
  waiting (that record is consumed and the pair completed), otherwise `:pending`
  after parking the record on the left side. A pending-left record with the same
  key is replaced by the new record (last write wins).
  """
  @spec push_left(GenServer.server(), record()) :: {:matched, entry()} | :pending
  def push_left(server, record) when is_map(record) do
    GenServer.call(server, {:push, :left, record})
  end

  @doc """
  Feeds one record from the right stream.

  Symmetric to `push_left/2`: it looks for a pending left record with the same
  key, and parks the record under pending-right otherwise.
  """
  @spec push_right(GenServer.server(), record()) :: {:matched, entry()} | :pending
  def push_right(server, record) when is_map(record) do
    GenServer.call(server, {:push, :right, record})
  end

  @doc """
  Drains and returns the buffered matched entries.

  Entries come back in the order their pairs were completed. The buffer is
  emptied, so an immediately following call returns `[]`.
  """
  @spec take_matches(GenServer.server()) :: [entry()]
  def take_matches(server) do
    GenServer.call(server, :take_matches)
  end

  @doc """
  Returns the records still awaiting a counterpart, as `%{left: [...], right: [...]}`.

  The records are the full original maps. The order within each list is
  unspecified. This call does not change any state.
  """
  @spec pending(GenServer.server()) :: %{left: [record()], right: [record()]}
  def pending(server) do
    GenServer.call(server, :pending)
  end

  @doc """
  Stops the server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:push, side, record}, _from, %State{} = state) do
    key = build_key(record, state.key_fields)

    case take_counterpart(state, side, key) do
      {:ok, counterpart, state} ->
        {left, right} = order_pair(side, record, counterpart)
        entry = build_entry(key, left, right, state)
        state = %State{state | matches: state.matches ++ [entry]}
        {:reply, {:matched, entry}, state}

      :error ->
        {:reply, :pending, park(state, side, key, record)}
    end
  end

  def handle_call(:take_matches, _from, %State{} = state) do
    {:reply, state.matches, %State{state | matches: []}}
  end

  def handle_call(:pending, _from, %State{} = state) do
    reply = %{
      left: Map.values(state.pending_left),
      right: Map.values(state.pending_right)
    }

    {:reply, reply, state}
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  @spec validate_key_fields(term()) :: [atom()]
  defp validate_key_fields(fields) do
    if is_list(fields) and fields != [] and Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":key_fields is required and must be a non-empty list of atoms, " <>
              "got: #{inspect(fields)}"
    end
  end

  @spec validate_compare_fields(term()) :: [atom()] | nil
  defp validate_compare_fields(nil), do: nil

  defp validate_compare_fields(fields) do
    if is_list(fields) and Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":compare_fields must be a list of atoms or nil, got: #{inspect(fields)}"
    end
  end

  @spec build_key(record(), [atom()]) :: key()
  defp build_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  @spec take_counterpart(State.t(), :left | :right, key()) ::
          {:ok, record(), State.t()} | :error
  defp take_counterpart(%State{} = state, :left, key) do
    case Map.pop(state.pending_right, key) do
      {nil, _rest} -> :error
      {counterpart, rest} -> {:ok, counterpart, %State{state | pending_right: rest}}
    end
  end

  defp take_counterpart(%State{} = state, :right, key) do
    case Map.pop(state.pending_left, key) do
      {nil, _rest} -> :error
      {counterpart, rest} -> {:ok, counterpart, %State{state | pending_left: rest}}
    end
  end

  @spec park(State.t(), :left | :right, key(), record()) :: State.t()
  defp park(%State{} = state, :left, key, record) do
    %State{state | pending_left: Map.put(state.pending_left, key, record)}
  end

  defp park(%State{} = state, :right, key, record) do
    %State{state | pending_right: Map.put(state.pending_right, key, record)}
  end

  @spec order_pair(:left | :right, record(), record()) :: {record(), record()}
  defp order_pair(:left, record, counterpart), do: {record, counterpart}
  defp order_pair(:right, record, counterpart), do: {counterpart, record}

  @spec build_entry(key(), record(), record(), State.t()) :: entry()
  defp build_entry(key, left, right, %State{} = state) do
    %{
      key: key_map(key, state.key_fields),
      left: left,
      right: right,
      differences: differences(left, right, state)
    }
  end

  @spec key_map(key(), [atom()]) :: map()
  defp key_map(key, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key))
    |> Map.new()
  end

  @spec differences(record(), record(), State.t()) :: map()
  defp differences(left, right, %State{} = state) do
    state
    |> fields_to_compare(left, right)
    |> Enum.reduce(%{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  @spec fields_to_compare(State.t(), record(), record()) :: [atom()]
  defp fields_to_compare(%State{compare_fields: nil} = state, left, right) do
    key_fields = MapSet.new(state.key_fields)

    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_fields, &1))
  end

  defp fields_to_compare(%State{compare_fields: fields}, _left, _right), do: fields
end