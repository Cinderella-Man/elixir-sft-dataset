defmodule ConcurrentRingBuffer do
  @moduledoc """
  A fixed-size, overwriting ring buffer backed by a `GenServer`.

  The buffer is pre-allocated as a tuple of `:capacity` slots. Integer read and write
  heads walk forward and wrap around with `rem/2`, so pushing never grows any structure
  and never copies the whole store. When the buffer is full, `push/2` silently overwrites
  the oldest item and advances the read head.

  Because every operation is a `GenServer` call or cast, the buffer can be shared freely
  across concurrent processes — for example as a live log tail or a metrics sink — without
  any risk of interleaved writers corrupting it.

  ## Example

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 3)
      iex> Enum.each(1..5, &ConcurrentRingBuffer.push(buf, &1))
      iex> ConcurrentRingBuffer.to_list(buf)
      [3, 4, 5]
      iex> ConcurrentRingBuffer.flush(buf)
      [3, 4, 5]
      iex> ConcurrentRingBuffer.size(buf)
      0
  """

  use GenServer

  @typedoc "A running buffer: a pid, a registered name, or any `t:GenServer.server/0`."
  @type server :: GenServer.server()

  @typedoc "Anything may be stored in the buffer."
  @type item :: term()

  defmodule State do
    @moduledoc false

    @enforce_keys [:slots, :capacity]
    defstruct slots: {}, capacity: 0, read: 0, write: 0, count: 0

    @type t :: %__MODULE__{
            slots: tuple(),
            capacity: pos_integer(),
            read: non_neg_integer(),
            write: non_neg_integer(),
            count: non_neg_integer()
          }
  end

  # ----------------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------------

  @doc """
  Starts a ring buffer server linked to the calling process.

  ## Options

    * `:capacity` — required, a positive integer; the number of pre-allocated slots.
    * `:name` — optional; a name to register the server under, as accepted by `GenServer`.

  Any other option is passed through to `GenServer.start_link/3`.

  Raises `ArgumentError` if `:capacity` is missing or is not a positive integer.

  ## Examples

      iex> {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 8)
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {capacity, opts} = Keyword.pop(opts, :capacity)
    capacity = validate_capacity!(capacity)
    GenServer.start_link(__MODULE__, capacity, opts)
  end

  @doc """
  Inserts `item` into the buffer, overwriting the oldest item when the buffer is full.

  Always returns `:ok`. The call is synchronous, so a returned `:ok` means the item is
  already stored — writers from many processes are serialized by the server.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 2)
      iex> ConcurrentRingBuffer.push(buf, :a)
      :ok
  """
  @spec push(server(), item()) :: :ok
  def push(server, item) do
    GenServer.call(server, {:push, item})
  end

  @doc """
  Returns every stored item in insertion order, from oldest to newest.

  The buffer is left untouched. Returns `[]` when empty.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 2)
      iex> ConcurrentRingBuffer.push(buf, :a)
      iex> ConcurrentRingBuffer.push(buf, :b)
      iex> ConcurrentRingBuffer.to_list(buf)
      [:a, :b]
  """
  @spec to_list(server()) :: [item()]
  def to_list(server) do
    GenServer.call(server, :to_list)
  end

  @doc """
  Returns the number of items currently stored, between `0` and the capacity.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 2)
      iex> ConcurrentRingBuffer.size(buf)
      0
  """
  @spec size(server()) :: non_neg_integer()
  def size(server) do
    GenServer.call(server, :size)
  end

  @doc """
  Returns `{:ok, item}` for the oldest stored item, or `:error` when the buffer is empty.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 2)
      iex> ConcurrentRingBuffer.peek_oldest(buf)
      :error
      iex> ConcurrentRingBuffer.push(buf, :a)
      iex> ConcurrentRingBuffer.peek_oldest(buf)
      {:ok, :a}
  """
  @spec peek_oldest(server()) :: {:ok, item()} | :error
  def peek_oldest(server) do
    GenServer.call(server, :peek_oldest)
  end

  @doc """
  Returns `{:ok, item}` for the newest stored item, or `:error` when the buffer is empty.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 2)
      iex> ConcurrentRingBuffer.push(buf, :a)
      iex> ConcurrentRingBuffer.push(buf, :b)
      iex> ConcurrentRingBuffer.peek_newest(buf)
      {:ok, :b}
  """
  @spec peek_newest(server()) :: {:ok, item()} | :error
  def peek_newest(server) do
    GenServer.call(server, :peek_newest)
  end

  @doc """
  Atomically drains the buffer.

  Returns every stored item, oldest to newest, and empties the buffer in the same
  operation. A draining consumer therefore never loses items pushed concurrently and
  never reads the same item twice.

  ## Examples

      iex> {:ok, buf} = ConcurrentRingBuffer.start_link(capacity: 3)
      iex> ConcurrentRingBuffer.push(buf, :a)
      iex> ConcurrentRingBuffer.flush(buf)
      [:a]
      iex> ConcurrentRingBuffer.flush(buf)
      []
  """
  @spec flush(server()) :: [item()]
  def flush(server) do
    GenServer.call(server, :flush)
  end

  # ----------------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------------

  @impl GenServer
  def init(capacity) do
    slots = Tuple.duplicate(nil, capacity)
    {:ok, %State{slots: slots, capacity: capacity}}
  end

  @impl GenServer
  def handle_call({:push, item}, _from, %State{} = state) do
    {:reply, :ok, do_push(state, item)}
  end

  def handle_call(:to_list, _from, %State{} = state) do
    {:reply, do_to_list(state), state}
  end

  def handle_call(:size, _from, %State{count: count} = state) do
    {:reply, count, state}
  end

  def handle_call(:peek_oldest, _from, %State{count: 0} = state) do
    {:reply, :error, state}
  end

  def handle_call(:peek_oldest, _from, %State{} = state) do
    {:reply, {:ok, elem(state.slots, state.read)}, state}
  end

  def handle_call(:peek_newest, _from, %State{count: 0} = state) do
    {:reply, :error, state}
  end

  def handle_call(:peek_newest, _from, %State{} = state) do
    newest = rem(state.write + state.capacity - 1, state.capacity)
    {:reply, {:ok, elem(state.slots, newest)}, state}
  end

  def handle_call(:flush, _from, %State{} = state) do
    items = do_to_list(state)
    emptied = %State{state | slots: Tuple.duplicate(nil, state.capacity), read: 0, write: 0,
                             count: 0}

    {:reply, items, emptied}
  end

  # ----------------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------------

  @spec validate_capacity!(term()) :: pos_integer()
  defp validate_capacity!(capacity) when is_integer(capacity) and capacity > 0, do: capacity

  defp validate_capacity!(other) do
    raise ArgumentError,
          "expected :capacity to be a positive integer, got: #{inspect(other)}"
  end

  @spec do_push(State.t(), item()) :: State.t()
  defp do_push(%State{capacity: capacity} = state, item) do
    slots = put_elem(state.slots, state.write, item)
    write = rem(state.write + 1, capacity)
    full? = state.count == capacity
    read = if full?, do: rem(state.read + 1, capacity), else: state.read
    count = if full?, do: capacity, else: state.count + 1

    %State{state | slots: slots, write: write, read: read, count: count}
  end

  @spec do_to_list(State.t()) :: [item()]
  defp do_to_list(%State{count: 0}), do: []

  defp do_to_list(%State{count: count, read: read, capacity: capacity, slots: slots}) do
    for offset <- 0..(count - 1), do: elem(slots, rem(read + offset, capacity))
  end
end