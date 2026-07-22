defmodule StreamReconciler do
  @moduledoc """
  A `GenServer` that reconciles two streams of record maps incrementally.

  Records arrive one at a time on the `left` or `right` side, in any interleaving. Each side
  keeps a buffer of records that have not yet found a partner, indexed by a composite key
  built from `:key_fields`. When a record arrives whose key is already pending on the *other*
  side, the pair is matched immediately: both records leave the buffers and a matched entry is
  appended to a queue that the caller drains with `take_matches/1`.

  A matched entry has the shape:

      %{
        key: %{id: 1},
        left: %{id: 1, name: "a"},
        right: %{id: 1, name: "b"},
        differences: %{name: %{left: "a", right: "b"}}
      }

  `:differences` only holds compared fields whose values differ (`==` comparison). When
  `:compare_fields` is not supplied, every field present in either record of the pair is
  compared, except the key fields. A compared field missing from a record is treated as `nil`.

  Same-side duplicate keys follow a last-write-wins rule: pushing a record whose key is already
  pending on that same side replaces the buffered record, which is dropped and never reported.

  ## Example

      {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
      :ok = StreamReconciler.push_left(pid, %{id: 1, name: "a"})
      :ok = StreamReconciler.push_right(pid, %{id: 1, name: "b"})
      [%{key: %{id: 1}}] = StreamReconciler.take_matches(pid)
      %{matched: [], only_in_left: [], only_in_right: []} = StreamReconciler.finalize(pid)
  """

  use GenServer

  @type record :: map()
  @type key_map :: %{optional(atom()) => term()}
  @type differences :: %{optional(atom()) => %{left: term(), right: term()}}
  @type matched_entry :: %{
          key: key_map(),
          left: record(),
          right: record(),
          differences: differences()
        }
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  defstruct key_fields: [],
            compare_fields: nil,
            left: %{},
            right: %{},
            matches: []

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the reconciler.

  Options:

    * `:key_fields` — required, a non-empty list of atoms forming the composite key.
    * `:compare_fields` — optional list of atoms to diff on matched records. When omitted or
      `nil`, all fields present in either record of the pair are compared, except key fields.
    * `:name` — optional name to register the process under; it may then be used in place of
      the pid in every other function.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    key_fields = Keyword.fetch!(opts, :key_fields)
    compare_fields = Keyword.get(opts, :compare_fields)

    validate_fields!(:key_fields, key_fields)
    validate_compare_fields!(compare_fields)

    if key_fields == [] do
      raise ArgumentError, ":key_fields must be a non-empty list of atoms"
    end

    init_arg = %{key_fields: key_fields, compare_fields: compare_fields}

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, init_arg, name: name)
      :error -> GenServer.start_link(__MODULE__, init_arg)
    end
  end

  @doc """
  Pushes one record map onto the left side.

  If the key is pending on the right side, the pair is matched immediately. If the key is
  already pending on the left side, the new record replaces the buffered one.

  Always returns `:ok`.
  """
  @spec push_left(GenServer.server(), record()) :: :ok
  def push_left(server, record) when is_map(record) do
    GenServer.call(server, {:push, :left, record})
  end

  @doc """
  Pushes one record map onto the right side.

  If the key is pending on the left side, the pair is matched immediately. If the key is
  already pending on the right side, the new record replaces the buffered one.

  Always returns `:ok`.
  """
  @spec push_right(GenServer.server(), record()) :: :ok
  def push_right(server, record) when is_map(record) do
    GenServer.call(server, {:push, :right, record})
  end

  @doc """
  Returns the matched entries produced since the last call (or since start), in the order the
  matches completed, and clears the queue.

  An immediate second call returns `[]`.
  """
  @spec take_matches(GenServer.server()) :: [matched_entry()]
  def take_matches(server) do
    GenServer.call(server, :take_matches)
  end

  @doc """
  Returns `%{left: n, right: m}` — the number of records currently buffered on each side
  awaiting a partner.
  """
  @spec pending_counts(GenServer.server()) :: %{left: non_neg_integer(), right: non_neg_integer()}
  def pending_counts(server) do
    GenServer.call(server, :pending_counts)
  end

  @doc """
  Returns `%{matched: [...], only_in_left: [...], only_in_right: [...]}` and then stops the
  server with reason `:normal`.

  `:matched` holds the matched entries not yet collected by `take_matches/1`; `:only_in_left`
  and `:only_in_right` hold the raw record maps still buffered on each side, in unspecified
  order.
  """
  @spec finalize(GenServer.server()) :: result()
  def finalize(server) do
    GenServer.call(server, :finalize)
  end

  @doc """
  Stops the server without producing a result. Returns `:ok`.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{key_fields: key_fields, compare_fields: compare_fields}) do
    {:ok, %__MODULE__{key_fields: key_fields, compare_fields: compare_fields}}
  end

  @impl true
  def handle_call({:push, side, record}, _from, state) do
    {:reply, :ok, push(state, side, record)}
  end

  def handle_call(:take_matches, _from, state) do
    {:reply, Enum.reverse(state.matches), %{state | matches: []}}
  end

  def handle_call(:pending_counts, _from, state) do
    {:reply, %{left: map_size(state.left), right: map_size(state.right)}, state}
  end

  def handle_call(:finalize, _from, state) do
    result = %{
      matched: Enum.reverse(state.matches),
      only_in_left: Map.values(state.left),
      only_in_right: Map.values(state.right)
    }

    {:stop, :normal, result, %{state | matches: []}}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec push(%__MODULE__{}, :left | :right, record()) :: %__MODULE__{}
  defp push(state, side, record) do
    key = build_key(record, state.key_fields)
    other = opposite(side)
    other_buffer = buffer(state, other)

    case Map.pop(other_buffer, key) do
      {nil, _rest} ->
        put_buffer(state, side, Map.put(buffer(state, side), key, record))

      {partner, rest} ->
        {left_record, right_record} =
          case side do
            :left -> {record, partner}
            :right -> {partner, record}
          end

        entry = build_entry(state, key, left_record, right_record)

        state
        |> put_buffer(other, rest)
        |> Map.update!(:matches, &[entry | &1])
    end
  end

  @spec build_entry(%__MODULE__{}, key_map(), record(), record()) :: matched_entry()
  defp build_entry(state, key, left_record, right_record) do
    %{
      key: key,
      left: left_record,
      right: right_record,
      differences: diff(state, left_record, right_record)
    }
  end

  @spec diff(%__MODULE__{}, record(), record()) :: differences()
  defp diff(state, left_record, right_record) do
    state
    |> fields_to_compare(left_record, right_record)
    |> Enum.reduce(%{}, fn field, acc ->
      left_value = Map.get(left_record, field)
      right_value = Map.get(right_record, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end

  @spec fields_to_compare(%__MODULE__{}, record(), record()) :: [atom()]
  defp fields_to_compare(%__MODULE__{compare_fields: nil} = state, left_record, right_record) do
    key_fields = MapSet.new(state.key_fields)

    left_record
    |> Map.keys()
    |> Enum.concat(Map.keys(right_record))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_fields, &1))
  end

  defp fields_to_compare(%__MODULE__{compare_fields: fields}, _left, _right), do: fields

  @spec build_key(record(), [atom()]) :: key_map()
  defp build_key(record, key_fields) do
    Map.new(key_fields, fn field -> {field, Map.get(record, field)} end)
  end

  @spec buffer(%__MODULE__{}, :left | :right) :: %{optional(key_map()) => record()}
  defp buffer(%__MODULE__{left: left}, :left), do: left
  defp buffer(%__MODULE__{right: right}, :right), do: right

  @spec put_buffer(%__MODULE__{}, :left | :right, %{optional(key_map()) => record()}) ::
          %__MODULE__{}
  defp put_buffer(state, :left, buffer), do: %{state | left: buffer}
  defp put_buffer(state, :right, buffer), do: %{state | right: buffer}

  @spec opposite(:left | :right) :: :left | :right
  defp opposite(:left), do: :right
  defp opposite(:right), do: :left

  @spec validate_fields!(atom(), term()) :: :ok
  defp validate_fields!(name, fields) do
    if is_list(fields) and Enum.all?(fields, &is_atom/1) do
      :ok
    else
      raise ArgumentError, "#{inspect(name)} must be a list of atoms, got: #{inspect(fields)}"
    end
  end

  @spec validate_compare_fields!(term()) :: :ok
  defp validate_compare_fields!(nil), do: :ok
  defp validate_compare_fields!(fields), do: validate_fields!(:compare_fields, fields)
end
