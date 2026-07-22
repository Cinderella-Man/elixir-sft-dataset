defmodule ValidatingPool do
  @moduledoc """
  A `GenServer`-based pool of reusable connections that **validates every connection
  right before handing it to a caller**.

  A "connection" is an opaque term produced by the `:create` factory function — a PID,
  a reference, a socket, or any value at all. The pool never hands out a connection that
  fails the `:validate` predicate: bad connections are destroyed (via `:destroy`), dropped
  from the pool, and replaced, so callers always receive a healthy connection.

  ## Behaviour

    * **Validation on the way out.** On `checkout/2`, available connections are tried one
      at a time. Each is validated; an invalid one is destroyed and removed from the pool
      (shrinking `total`) and the next candidate is tried.
    * **Lazy growth.** When nothing valid is available and the pool holds fewer than
      `:max_size` connections, a fresh one is created on demand (assumed valid) and handed
      out immediately.
    * **Blocking with a server-side timeout.** When the pool is saturated, the caller is
      parked in a FIFO waiter queue. `Process.send_after/3` plus `GenServer.reply/2` deliver
      either `{:ok, conn}` or `{:error, :timeout}` as a normal return value.
    * **Validation on the way in.** A connection returned by `checkin/2` (or reclaimed from a
      crashed owner) is validated before being handed to the longest-waiting caller. If it
      fails, it is destroyed and a fresh connection is created for that waiter instead.
    * **Crash reclamation.** The checking-out process is monitored; if it dies while holding a
      connection, the connection is reclaimed (and validated before reuse).

  ## Example

      {:ok, _pid} =
        ValidatingPool.start_link(
          name: :db_pool,
          max_size: 5,
          min_size: 2,
          create: fn -> MyDB.connect!() end,
          validate: &MyDB.alive?/1,
          destroy: &MyDB.close/1
        )

      {:ok, conn} = ValidatingPool.checkout(:db_pool, 1_000)
      :ok = ValidatingPool.checkin(:db_pool, conn)
  """

  use GenServer

  @type conn :: term()
  @type pool :: GenServer.server()

  @type option ::
          {:name, atom()}
          | {:max_size, pos_integer()}
          | {:min_size, non_neg_integer()}
          | {:create, (-> conn())}
          | {:validate, (conn() -> boolean())}
          | {:destroy, (conn() -> any())}

  @type stats :: %{
          available: non_neg_integer(),
          in_use: non_neg_integer(),
          total: non_neg_integer(),
          max: pos_integer(),
          min: non_neg_integer()
        }

  @default_max_size 10
  @default_min_size 0
  @default_checkout_timeout 5_000

  defstruct available: [],
            in_use: %{},
            waiters: :queue.new(),
            monitors: %{},
            max_size: @default_max_size,
            min_size: @default_min_size,
            create: nil,
            validate: nil,
            destroy: nil

  # A waiter parked in the queue while the pool is saturated.
  defmodule Waiter do
    @moduledoc false
    defstruct [:wref, :from, :pid, :mref, :timer]
  end

  ## Public API

  @doc """
  Starts a pool.

  Options:

    * `:name` — atom to register the process under.
    * `:max_size` — maximum number of connections alive at once (default `10`).
    * `:min_size` — connections created eagerly at startup (default `0`, must be
      `<= :max_size`).
    * `:create` — zero-arity function returning a new, distinct connection
      (default `fn -> make_ref() end`).
    * `:validate` — one-arity predicate run just before a connection is handed out
      (default `fn _ -> true end`).
    * `:destroy` — one-arity function called when a connection is discarded
      (default a no-op).

  Raises `ArgumentError` when the sizes are inconsistent.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    gen_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} when is_atom(name) -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Borrows a valid connection from `pool`.

  Returns `{:ok, conn}` with a connection that has just passed `:validate` (or a freshly
  created one). When the pool is at `:max_size` with nothing available, the caller blocks
  for up to `timeout` milliseconds and receives `{:error, :timeout}` if no connection is
  returned in time. A `timeout` of `0` never blocks.
  """
  @spec checkout(pool(), timeout()) :: {:ok, conn()} | {:error, :timeout}
  def checkout(pool, timeout \\ @default_checkout_timeout)
      when timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
    GenServer.call(pool, {:checkout, timeout}, :infinity)
  end

  @doc """
  Returns `conn` to `pool`, making it available again.

  If a caller is blocked waiting, `conn` is validated first; if it fails validation it is
  destroyed and a fresh connection is created for the longest-waiting caller. Checking in a
  connection the pool does not know about is a no-op. Always returns `:ok`.
  """
  @spec checkin(pool(), conn()) :: :ok
  def checkin(pool, conn) do
    GenServer.call(pool, {:checkin, conn}, :infinity)
  end

  @doc """
  Returns pool counters as `%{available: a, in_use: u, total: t, max: max, min: min}`,
  where `total == available + in_use`.
  """
  @spec stats(pool()) :: stats()
  def stats(pool) do
    GenServer.call(pool, :stats, :infinity)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    min_size = Keyword.get(opts, :min_size, @default_min_size)

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    unless is_integer(min_size) and min_size >= 0 do
      raise ArgumentError, ":min_size must be a non-negative integer, got: #{inspect(min_size)}"
    end

    unless min_size <= max_size do
      raise ArgumentError, ":min_size (#{min_size}) must be <= :max_size (#{max_size})"
    end

    state = %__MODULE__{
      max_size: max_size,
      min_size: min_size,
      create: Keyword.get(opts, :create, fn -> make_ref() end),
      validate: Keyword.get(opts, :validate, fn _conn -> true end),
      destroy: Keyword.get(opts, :destroy, fn _conn -> :ok end)
    }

    eager = for _ <- 1..min_size//1, do: state.create.()

    {:ok, %{state | available: eager}}
  end

  @impl true
  def handle_call({:checkout, timeout}, {pid, _tag} = from, state) do
    case take_valid(state) do
      {:ok, conn, state} ->
        {:reply, {:ok, conn}, assign(state, conn, pid)}

      {:none, state} ->
        cond do
          total(state) < state.max_size ->
            conn = state.create.()
            {:reply, {:ok, conn}, assign(state, conn, pid)}

          timeout == 0 ->
            {:reply, {:error, :timeout}, state}

          true ->
            {:noreply, enqueue_waiter(state, from, pid, timeout)}
        end
    end
  end

  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.in_use, conn) do
      {nil, _in_use} ->
        {:reply, :ok, state}

      {{_pid, mref}, in_use} ->
        Process.demonitor(mref, [:flush])
        state = %{state | in_use: in_use, monitors: Map.delete(state.monitors, mref)}
        {:reply, :ok, release(state, conn)}
    end
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      available: length(state.available),
      in_use: map_size(state.in_use),
      total: total(state),
      max: state.max_size,
      min: state.min_size
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:waiter_timeout, wref}, state) do
    case pop_waiter(state, wref) do
      {nil, state} ->
        {:noreply, state}

      {waiter, state} ->
        state = forget_monitor(state, waiter.mref)
        GenServer.reply(waiter.from, {:error, :timeout})
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, mref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, mref) do
      {nil, _monitors} ->
        {:noreply, state}

      {{:conn, conn}, monitors} ->
        state = %{state | monitors: monitors, in_use: Map.delete(state.in_use, conn)}
        {:noreply, release(state, conn)}

      {{:waiter, wref}, monitors} ->
        {_waiter, state} = pop_waiter(%{state | monitors: monitors}, wref)
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Internal helpers

  # Pops the first available connection that passes validation, destroying and dropping any
  # that fail on the way. Shrinks the pool for each discarded connection.
  defp take_valid(%__MODULE__{available: []} = state), do: {:none, state}

  defp take_valid(%__MODULE__{available: [conn | rest]} = state) do
    state = %{state | available: rest}

    if state.validate.(conn) do
      {:ok, conn, state}
    else
      state.destroy.(conn)
      take_valid(state)
    end
  end

  # Marks `conn` as in use by `pid`, monitoring the owner so a crash reclaims it.
  defp assign(state, conn, pid) do
    mref = Process.monitor(pid)

    %{
      state
      | in_use: Map.put(state.in_use, conn, {pid, mref}),
        monitors: Map.put(state.monitors, mref, {:conn, conn})
    }
  end

  # Hands a reclaimed connection to the longest-waiting caller (validating it first) or puts
  # it back into the available set. `conn` must already have been removed from `in_use`.
  defp release(state, conn) do
    case :queue.out(state.waiters) do
      {:empty, _queue} ->
        %{state | available: state.available ++ [conn]}

      {{:value, waiter}, rest} ->
        state = %{state | waiters: rest}
        cancel_timer(waiter.timer)

        if state.validate.(conn) do
          hand_to_waiter(state, waiter, conn)
        else
          state.destroy.(conn)
          hand_to_waiter(state, waiter, state.create.())
        end
    end
  end

  # Replies to a parked caller, promoting its waiter monitor into an ownership monitor.
  defp hand_to_waiter(state, %Waiter{} = waiter, conn) do
    state = %{
      state
      | in_use: Map.put(state.in_use, conn, {waiter.pid, waiter.mref}),
        monitors: Map.put(state.monitors, waiter.mref, {:conn, conn})
    }

    GenServer.reply(waiter.from, {:ok, conn})
    state
  end

  defp enqueue_waiter(state, from, pid, timeout) do
    wref = make_ref()
    mref = Process.monitor(pid)

    timer =
      case timeout do
        :infinity -> nil
        ms -> Process.send_after(self(), {:waiter_timeout, wref}, ms)
      end

    waiter = %Waiter{wref: wref, from: from, pid: pid, mref: mref, timer: timer}

    %{
      state
      | waiters: :queue.in(waiter, state.waiters),
        monitors: Map.put(state.monitors, mref, {:waiter, wref})
    }
  end

  # Removes a waiter from the queue by its reference, cancelling its timer. Returns `nil` when
  # the waiter is gone already (e.g. it was just served and a stale timeout message arrived).
  defp pop_waiter(state, wref) do
    waiters = :queue.to_list(state.waiters)

    case Enum.split_with(waiters, &(&1.wref == wref)) do
      {[], _rest} ->
        {nil, state}

      {[waiter | _dups], rest} ->
        cancel_timer(waiter.timer)
        {waiter, %{state | waiters: :queue.from_list(rest)}}
    end
  end

  defp forget_monitor(state, mref) do
    Process.demonitor(mref, [:flush])
    %{state | monitors: Map.delete(state.monitors, mref)}
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp total(state), do: length(state.available) + map_size(state.in_use)
end