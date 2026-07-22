defmodule KeyedAggregator do
  @moduledoc """
  A `GenServer` that collects events partitioned by key and flushes each key's
  events to a callback in batches.

  Every key maintains its own independent buffer and its own flush timer. A key is
  flushed when either that key's buffer reaches `:batch_size` events, or when
  `:interval_ms` milliseconds have elapsed since the first push of the key's current
  batch — whichever comes first.

  Flushing a key resets it completely: the buffer is emptied, the count returns to
  zero, and any pending timer is cancelled. Keys never interfere with one another.

  ## Example

      {:ok, pid} =
        KeyedAggregator.start_link(
          batch_size: 3,
          interval_ms: 50,
          on_flush: fn key, batch -> IO.inspect({key, batch}) end
        )

      KeyedAggregator.push(pid, :a, 1)
      KeyedAggregator.push(pid, :a, 2)
      KeyedAggregator.push(pid, :a, 3)
      #=> callback receives {:a, [1, 2, 3]}
  """

  use GenServer

  @default_batch_size 100
  @default_interval_ms 1_000

  @typedoc "A key under which events are partitioned. May be any term."
  @type key :: term()

  @typedoc "An individual buffered event. May be any term."
  @type event :: term()

  @typedoc "The callback invoked with a key and its flushed batch of events."
  @type on_flush :: (key(), [event()] -> any())

  @typedoc "A pid or registered name referring to a running aggregator."
  @type server :: GenServer.server()

  # Per-key entry: events are accumulated in reverse order for O(1) prepend and
  # reversed on flush, preserving per-key push ordering.
  defmodule Entry do
    @moduledoc false
    defstruct rev_events: [], count: 0, timer_ref: nil
  end

  defmodule State do
    @moduledoc false
    defstruct [:batch_size, :interval_ms, :on_flush, entries: %{}]
  end

  @doc """
  Starts the aggregator.

  Supported options:

    * `:batch_size` — positive integer; flush a key once it holds this many events
      (default `#{@default_batch_size}`).
    * `:interval_ms` — positive integer; flush a key this many milliseconds after the
      first push of its current batch (default `#{@default_interval_ms}`).
    * `:on_flush` — a two-arity function called as `on_flush.(key, batch)` on every
      flush (default: a no-op).
    * `:name` — optional process registration name, passed through to
      `GenServer.start_link/3`.

  Returns whatever `GenServer.start_link/3` returns.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Buffers `event` under `key` on the aggregator referenced by `server`.

  This call is asynchronous and fire-and-forget: it always returns `:ok` immediately,
  possibly before any flush or callback invocation has happened. Both `key` and
  `event` may be any term.
  """
  @spec push(server(), key(), event()) :: :ok
  def push(server, key, event) do
    GenServer.cast(server, {:push, key, event})
  end

  @impl GenServer
  def init(opts) do
    state = %State{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      on_flush: Keyword.get(opts, :on_flush, fn _key, _batch -> :ok end),
      entries: %{}
    }

    {:noreply, state} |> elem(1) |> then(&{:ok, &1})
  end

  @impl GenServer
  def handle_cast({:push, key, event}, state) do
    entry = Map.get(state.entries, key, %Entry{})

    entry = %Entry{
      entry
      | rev_events: [event | entry.rev_events],
        count: entry.count + 1,
        timer_ref: arm_timer(entry, key, state.interval_ms)
    }

    if entry.count >= state.batch_size do
      {:noreply, flush_key(state, key, entry)}
    else
      {:noreply, %State{state | entries: Map.put(state.entries, key, entry)}}
    end
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:flush, key, timer_ref}, state) do
    case Map.get(state.entries, key) do
      %Entry{timer_ref: ^timer_ref, count: count} = entry when count > 0 ->
        {:noreply, flush_key(state, key, entry)}

      _stale_or_missing ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Arms a fresh timer only when the key's buffer was empty before this push; an
  # already-armed timer keeps its original deadline.
  @spec arm_timer(Entry.t(), key(), pos_integer()) :: reference()
  defp arm_timer(%Entry{timer_ref: nil}, key, interval_ms) do
    ref = make_ref()
    Process.send_after(self(), {:flush, key, ref}, interval_ms)
    ref
  end

  defp arm_timer(%Entry{timer_ref: ref}, _key, _interval_ms), do: ref

  # Invokes the callback with the key's batch (in push order) and drops the key's
  # entry entirely, which zeroes its buffer, count, and timer.
  @spec flush_key(State.t(), key(), Entry.t()) :: State.t()
  defp flush_key(state, key, %Entry{rev_events: rev_events}) do
    state.on_flush.(key, Enum.reverse(rev_events))
    %State{state | entries: Map.delete(state.entries, key)}
  end
end