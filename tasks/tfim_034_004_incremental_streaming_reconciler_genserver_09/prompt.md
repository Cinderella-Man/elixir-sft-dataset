# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule StreamReconcilerTest do
  use ExUnit.Case, async: false

  defp start!(opts) do
    {:ok, pid} = StreamReconciler.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: StreamReconciler.stop(pid) end)
    pid
  end

  defp sorted_ids(records), do: records |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # Lifecycle / options
  # ---------------------------------------------------------------------------

  test "start_link returns a live pid and stop/1 shuts it down" do
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
    assert Process.alive?(pid)
    assert StreamReconciler.stop(pid) == :ok
    refute Process.alive?(pid)
  end

  test "missing key_fields raises ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link([]) end
  end

  test "invalid key_fields raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: []) end
    assert_raise ArgumentError, fn -> StreamReconciler.start_link(key_fields: ["id"]) end
  end

  test "server can be registered under a name" do
    name = :"stream_reconciler_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id], name: name)
    on_exit(fn -> if Process.alive?(pid), do: StreamReconciler.stop(name) end)

    assert StreamReconciler.push_left(name, %{id: 1}) == :pending
    assert %{left: [%{id: 1}], right: []} = StreamReconciler.pending(name)
  end

  # ---------------------------------------------------------------------------
  # Push semantics
  # ---------------------------------------------------------------------------

  test "an unmatched left push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice"}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == [%{id: 1, name: "Alice"}]
    assert pending.right == []
    assert StreamReconciler.take_matches(pid) == []
  end

  test "an unmatched right push is parked as pending" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_right(pid, %{id: 2}) == :pending

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{id: 2}]
  end

  test "a right push completing a pending left returns the matched entry" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, name: "Alice", age: 30}) == :pending

    assert {:matched, entry} =
             StreamReconciler.push_right(pid, %{id: 1, name: "Alice", age: 31})

    assert entry.key == %{id: 1}
    assert entry.left == %{id: 1, name: "Alice", age: 30}
    assert entry.right == %{id: 1, name: "Alice", age: 31}
    assert entry.differences == %{age: %{left: 30, right: 31}}
  end

  test "a left push completing a pending right keeps sides straight" do
    # TODO
  end

  test "a completed pair is removed from pending" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    assert StreamReconciler.pending(pid) == %{left: [], right: []}
  end

  test "identical records match with an empty differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice"})

    assert entry.differences == %{}
  end

  test "a compared field missing from one record diffs as nil" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, score: 42})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1})

    assert entry.differences == %{score: %{left: 42, right: nil}}
  end

  test "key fields never appear in the differences map" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, a: 1})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, a: 2})

    assert entry.differences == %{a: %{left: 1, right: 2}}
  end

  test "a duplicate pending push on the same side replaces the older record" do
    pid = start!(key_fields: [:id])

    assert StreamReconciler.push_left(pid, %{id: 1, v: "first"}) == :pending
    assert StreamReconciler.push_left(pid, %{id: 1, v: "second"}) == :pending

    assert StreamReconciler.pending(pid) == %{left: [%{id: 1, v: "second"}], right: []}

    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, v: "second"})
    assert entry.left == %{id: 1, v: "second"}
    assert entry.differences == %{}
  end

  # ---------------------------------------------------------------------------
  # compare_fields
  # ---------------------------------------------------------------------------

  test "compare_fields restricts the diff but records stay complete" do
    pid = start!(key_fields: [:id], compare_fields: [:name])

    StreamReconciler.push_left(pid, %{id: 1, name: "Alice", internal: "old"})
    {:matched, entry} = StreamReconciler.push_right(pid, %{id: 1, name: "Alice", internal: "new"})

    assert entry.differences == %{}
    assert entry.left.internal == "old"
    assert entry.right.internal == "new"
  end

  # ---------------------------------------------------------------------------
  # Composite keys
  # ---------------------------------------------------------------------------

  test "composite keys only match when every key field agrees" do
    pid = start!(key_fields: [:org_id, :user_id])

    assert StreamReconciler.push_left(pid, %{org_id: 1, user_id: 10}) == :pending
    assert StreamReconciler.push_right(pid, %{org_id: 2, user_id: 10}) == :pending

    assert {:matched, entry} = StreamReconciler.push_right(pid, %{org_id: 1, user_id: 10})
    assert entry.key == %{org_id: 1, user_id: 10}

    pending = StreamReconciler.pending(pid)
    assert pending.left == []
    assert pending.right == [%{org_id: 2, user_id: 10}]
  end

  # ---------------------------------------------------------------------------
  # take_matches
  # ---------------------------------------------------------------------------

  test "take_matches returns entries in completion order and empties the buffer" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    StreamReconciler.push_left(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 2})
    {:matched, _} = StreamReconciler.push_right(pid, %{id: 1})

    matches = StreamReconciler.take_matches(pid)
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    assert StreamReconciler.take_matches(pid) == []
  end

  test "take_matches on a fresh server is empty" do
    pid = start!(key_fields: [:id])
    assert StreamReconciler.take_matches(pid) == []
  end

  test "pending does not clear the pending sets" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1})
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
    assert %{left: [%{id: 1}]} = StreamReconciler.pending(pid)
  end

  # ---------------------------------------------------------------------------
  # Interleaved stream integration
  # ---------------------------------------------------------------------------

  test "interleaved out-of-order streams reconcile correctly" do
    pid = start!(key_fields: [:id])

    StreamReconciler.push_left(pid, %{id: 1, status: "active"})
    StreamReconciler.push_right(pid, %{id: 3, status: "active"})
    StreamReconciler.push_left(pid, %{id: 2, status: "active"})
    StreamReconciler.push_right(pid, %{id: 2, status: "inactive"})
    StreamReconciler.push_right(pid, %{id: 1, status: "active"})
    StreamReconciler.push_left(pid, %{id: 4, status: "new"})

    matches = StreamReconciler.take_matches(pid)
    assert length(matches) == 2
    assert Enum.map(matches, & &1.key) == [%{id: 2}, %{id: 1}]

    bob = Enum.find(matches, &(&1.key == %{id: 2}))
    assert bob.differences == %{status: %{left: "active", right: "inactive"}}

    alice = Enum.find(matches, &(&1.key == %{id: 1}))
    assert alice.differences == %{}

    pending = StreamReconciler.pending(pid)
    assert sorted_ids(pending.left) == [4]
    assert sorted_ids(pending.right) == [3]
  end

  test "two servers keep independent state" do
    a = start!(key_fields: [:id])
    b = start!(key_fields: [:id])

    StreamReconciler.push_left(a, %{id: 1})
    assert StreamReconciler.pending(b) == %{left: [], right: []}

    assert StreamReconciler.push_right(b, %{id: 1}) == :pending
    assert StreamReconciler.take_matches(a) == []
    assert StreamReconciler.take_matches(b) == []
  end
end
```
