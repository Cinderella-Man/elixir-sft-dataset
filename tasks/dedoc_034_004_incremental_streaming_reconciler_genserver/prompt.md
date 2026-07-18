# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule StreamReconciler do
  use GenServer

  defstruct key_fields: [],
            compare_fields: nil,
            pending_left: %{},
            pending_right: %{},
            matches: []

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  def start_link(opts) when is_list(opts) do
    key_fields = validate_key_fields!(Keyword.get(opts, :key_fields))
    compare_fields = validate_compare_fields!(Keyword.get(opts, :compare_fields))

    state = %__MODULE__{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, state, name: name)
      :error -> GenServer.start_link(__MODULE__, state)
    end
  end

  def push_left(server, record) when is_map(record) do
    GenServer.call(server, {:push, :left, record})
  end

  def push_right(server, record) when is_map(record) do
    GenServer.call(server, {:push, :right, record})
  end

  def take_matches(server) do
    GenServer.call(server, :take_matches)
  end

  def pending(server) do
    GenServer.call(server, :pending)
  end

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

  defp record_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  defp opposite(:left), do: :right
  defp opposite(:right), do: :left

  defp orient(:left, record, counterpart), do: {record, counterpart}
  defp orient(:right, record, counterpart), do: {counterpart, record}

  defp take_pending(state, side, key) do
    field = pending_field(side)
    map = Map.fetch!(state, field)

    case Map.pop(map, key) do
      {nil, _rest} -> :error
      {record, rest} -> {:ok, record, Map.put(state, field, rest)}
    end
  end

  defp put_pending(state, side, key, record) do
    field = pending_field(side)
    Map.put(state, field, Map.put(Map.fetch!(state, field), key, record))
  end

  defp pending_field(:left), do: :pending_left
  defp pending_field(:right), do: :pending_right

  defp build_entry(state, key, left, right) do
    %{
      key: key_map(state.key_fields, key),
      left: left,
      right: right,
      differences: differences(state, left, right)
    }
  end

  defp key_map(key_fields, key) do
    key_fields
    |> Enum.zip(Tuple.to_list(key))
    |> Map.new()
  end

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
