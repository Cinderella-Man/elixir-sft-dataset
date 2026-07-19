# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`validate_compare_fields!/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `validate_compare_fields!/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `validate_compare_fields!/1` missing

```elixir
defmodule StreamReconciler do
  @moduledoc """
  A `GenServer` that reconciles two record streams incrementally.

  Records from a left feed and a right feed are pushed in one at a time, possibly
  interleaved and out of order. Each record is parked as *pending* under its composite
  key until a counterpart arrives on the opposite side. When a pair completes, a matched
  entry is produced immediately (returned from the push) and appended to an internal
  buffer that can be drained with `take_matches/1`.

  A matched entry has the shape:

      %{key: key_map, left: left_record, right: right_record, differences: diff_map}

  where `diff_map` maps each compared field whose values differ to
  `%{left: left_value, right: right_value}`.

  ## Options

    * `:key_fields` (required) — non-empty list of atoms forming the composite key.
    * `:compare_fields` (optional) — list of atoms to diff on a completed pair. When
      omitted or `nil`, every field present in either record of the pair is compared,
      minus the key fields.
    * `:name` (optional) — name to register the server under.

  ## Example

      {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
      :pending = StreamReconciler.push_left(pid, %{id: 1, amount: 10})
      {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, amount: 12})
      entry.differences
      #=> %{amount: %{left: 10, right: 12}}

  """

  use GenServer

  @typedoc "A record from either stream."
  @type stream_record :: map()

  @typedoc "The composite key of a record: the tuple of its values at the key fields."
  @type key :: tuple()

  @typedoc "A completed pair."
  @type entry :: %{
          key: map(),
          left: stream_record(),
          right: stream_record(),
          differences: %{optional(atom()) => %{left: term(), right: term()}}
        }

  defstruct key_fields: [],
            compare_fields: nil,
            pending_left: %{},
            pending_right: %{},
            matches: []

  @typep state :: %__MODULE__{
           key_fields: [atom(), ...],
           compare_fields: [atom()] | nil,
           pending_left: %{optional(key()) => stream_record()},
           pending_right: %{optional(key()) => stream_record()},
           matches: [entry()]
         }

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the reconciler.

  Requires `:key_fields`, a non-empty list of atoms. Accepts optional `:compare_fields`
  and `:name`. Raises `ArgumentError` if `:key_fields` is missing or malformed.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields = validate_key_fields!(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields!(Keyword.get(opts, :compare_fields))

    state = %__MODULE__{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, state, name: name)
      :error -> GenServer.start_link(__MODULE__, state)
    end
  end

  @doc """
  Feeds one record from the left stream.

  Returns `{:matched, entry}` if a pending right record with the same key existed,
  otherwise `:pending` (parking the record, replacing any pending-left record with the
  same key).
  """
  @spec push_left(GenServer.server(), stream_record()) :: {:matched, entry()} | :pending
  def push_left(server, record) when is_map(record) do
    GenServer.call(server, {:push, :left, record})
  end

  @doc """
  Feeds one record from the right stream.

  Symmetric to `push_left/2`.
  """
  @spec push_right(GenServer.server(), stream_record()) :: {:matched, entry()} | :pending
  def push_right(server, record) when is_map(record) do
    GenServer.call(server, {:push, :right, record})
  end

  @doc """
  Drains and returns the buffered matched entries, in pair-completion order.

  The buffer is emptied, so an immediately following call returns `[]`.
  """
  @spec take_matches(GenServer.server()) :: [entry()]
  def take_matches(server) do
    GenServer.call(server, :take_matches)
  end

  @doc """
  Returns `%{left: [records], right: [records]}` — records awaiting a counterpart.

  Order within each list is unspecified. Does not change state.
  """
  @spec pending(GenServer.server()) :: %{left: [stream_record()], right: [stream_record()]}
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
  def init(%__MODULE__{} = state), do: {:ok, state}

  @impl GenServer
  def handle_call({:push, side, record}, _from, state) do
    key = record_key(record, state.key_fields)

    case take_pending(state, opposite(side), key) do
      {:ok, counterpart, state} ->
        {left, right} = orient(side, record, counterpart)
        entry = build_entry(state, key, left, right)
        state = %{state | matches: state.matches ++ [entry]}
        {:reply, {:matched, entry}, state}

      :error ->
        {:reply, :pending, put_pending(state, side, key, record)}
    end
  end

  def handle_call(:take_matches, _from, state) do
    {:reply, state.matches, %{state | matches: []}}
  end

  def handle_call(:pending, _from, state) do
    reply = %{
      left: Map.values(state.pending_left),
      right: Map.values(state.pending_right)
    }

    {:reply, reply, state}
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  @spec validate_key_fields!(term()) :: [atom(), ...]
  defp validate_key_fields!(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError,
            ":key_fields must be a non-empty list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_key_fields!(other) do
    raise ArgumentError, ":key_fields must be a non-empty list of atoms, got: #{inspect(other)}"
  end

  # TODO: @spec
  defp validate_compare_fields!(nil), do: nil

  defp validate_compare_fields!(fields) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1) do
      fields
    else
      raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  defp validate_compare_fields!(other) do
    raise ArgumentError, ":compare_fields must be a list of atoms, got: #{inspect(other)}"
  end

  @spec record_key(stream_record(), [atom(), ...]) :: key()
  defp record_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  @spec opposite(:left | :right) :: :left | :right
  defp opposite(:left), do: :right
  defp opposite(:right), do: :left

  @spec orient(:left | :right, stream_record(), stream_record()) ::
          {stream_record(), stream_record()}
  defp orient(:left, record, counterpart), do: {record, counterpart}
  defp orient(:right, record, counterpart), do: {counterpart, record}

  @spec take_pending(state(), :left | :right, key()) ::
          {:ok, stream_record(), state()} | :error
  defp take_pending(state, side, key) do
    field = pending_field(side)
    map = Map.fetch!(state, field)

    case Map.pop(map, key) do
      {nil, _rest} -> :error
      {record, rest} -> {:ok, record, Map.put(state, field, rest)}
    end
  end

  @spec put_pending(state(), :left | :right, key(), stream_record()) :: state()
  defp put_pending(state, side, key, record) do
    field = pending_field(side)
    Map.put(state, field, Map.put(Map.fetch!(state, field), key, record))
  end

  @spec pending_field(:left | :right) :: :pending_left | :pending_right
  defp pending_field(:left), do: :pending_left
  defp pending_field(:right), do: :pending_right

  @spec build_entry(state(), key(), stream_record(), stream_record()) :: entry()
  defp build_entry(state, key, left, right) do
    %{
      key: key_map(state.key_fields, key),
      left: left,
      right: right,
      differences: differences(state, left, right)
    }
  end

  @spec key_map([atom(), ...], key()) :: map()
  defp key_map(key_fields, key) do
    key_fields
    |> Enum.zip(Tuple.to_list(key))
    |> Map.new()
  end

  @spec differences(state(), stream_record(), stream_record()) :: %{
          optional(atom()) => %{left: term(), right: term()}
        }
  defp differences(state, left, right) do
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

  @spec fields_to_compare(state(), stream_record(), stream_record()) :: [atom()]
  defp fields_to_compare(%__MODULE__{compare_fields: nil} = state, left, right) do
    key_fields = MapSet.new(state.key_fields)

    left
    |> Map.keys()
    |> Kernel.++(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_fields, &1))
  end

  defp fields_to_compare(%__MODULE__{compare_fields: fields}, _left, _right), do: fields
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
