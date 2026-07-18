# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `validate_key_fields!` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `StreamReconciler` — a GenServer that reconciles two record streams **incrementally**, as records arrive one at a time from either side, instead of taking two complete lists.

The idea: records from the left feed and the right feed trickle in interleaved and out of order. Each unmatched record is parked as *pending* until its counterpart shows up on the other side; when a pair completes, a matched entry is produced immediately and also buffered for later collection.

## Public API

- `StreamReconciler.start_link(opts)` — starts the server, returns `{:ok, pid}`.
- `StreamReconciler.push_left(server, record)` — feeds one map from the left stream.
- `StreamReconciler.push_right(server, record)` — feeds one map from the right stream.
- `StreamReconciler.take_matches(server)` — drains and returns the buffered matched entries.
- `StreamReconciler.pending(server)` — returns the records still waiting for a counterpart.
- `StreamReconciler.stop(server)` — stops the server, returns `:ok`.

`server` is a pid (or a registered name if `:name` was given).

## Options for start_link/1

- `:key_fields` (required) — a non-empty list of atoms forming the composite key. If it is missing, or is not a non-empty list of atoms, raise `ArgumentError`.
- `:compare_fields` (optional) — a list of atoms to diff on a completed pair. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.
- `:name` (optional) — a name to register the server under, passed through to `GenServer`.

## Push semantics

A record's composite key is the tuple of its values at the key fields, in order; a key field missing from the record contributes `nil`.

`push_left(server, record)`:

- If a **pending right** record with the same key exists, it is removed from pending, the pair is completed, and the call returns `{:matched, entry}`.
- Otherwise the record is parked as pending-left and the call returns `:pending`. If a pending-left record with the same key already exists, the **new record replaces it** (last write wins).

`push_right/2` is exactly symmetric (it looks for a pending **left** record, and parks under pending-right otherwise).

A completed pair produces:

    %{key: key_map, left: left_record, right: right_record, differences: diff_map}

- `key_map` is `%{key_field => value}` for the pair's key.
- `left` / `right` are always the full original records from their respective sides, regardless of which push completed the pair.
- `diff_map` is `%{field => %{left: left_value, right: right_value}}` for each compared field whose values differ under `==`, and `%{}` when the pair agrees on all compared fields. A compared field missing from a record is treated as `nil`.

Every entry returned by a push is **also appended to an internal match buffer**.

## take_matches/1

Returns the buffered matched entries **in the order their pairs were completed**, and empties the buffer — so an immediately following `take_matches/1` returns `[]`.

## pending/1

Returns `%{left: [records], right: [records]}` — the records currently parked on each side awaiting a counterpart, as full original maps. The order within each list is unspecified. Calling `pending/1` does not change any state.

## Constraints

- Use OTP: `GenServer` only, no ETS, no external dependencies.
- All calls must be synchronous enough that a push's effect is visible to a subsequent `take_matches/1` or `pending/1` from the same caller.

Give me the complete module in a single file.

## The module with `validate_key_fields!` missing

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

  defp validate_key_fields!(fields) when is_list(fields) and fields != [] do
    # TODO
  end

  @spec validate_compare_fields!(term()) :: [atom()] | nil
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

Give me only the complete implementation of `validate_key_fields!` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
