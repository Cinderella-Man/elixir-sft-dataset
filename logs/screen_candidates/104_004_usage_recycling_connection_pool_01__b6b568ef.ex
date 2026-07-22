defmodule RecyclingPool do
  @moduledoc """
  A `GenServer` connection pool that retires each connection after a fixed number of uses.

  Connections are opaque terms produced by a user-supplied `:create` function. The pool
  grows lazily up to `:max_size`, optionally pre-creating `:min_size` connections at
  startup. Every completed use — a checkout followed by a check-in, or a checkout whose
  owner crashes — increments the connection's use count. Once a connection reaches
  `:max_uses` it is destroyed via the `:destroy` callback and the pool shrinks; a
  replacement is created lazily on the next demand (or immediately, for the longest-waiting
  blocked caller).

  Waiting and timeouts are handled entirely server-side with a FIFO waiter queue and
  `Process.send_after/3`, so a blocked `checkout/2` returns `{:error, :timeout}` as an
  ordinary value rather than exiting.

  ## Example

      {:ok, _pid} = RecyclingPool.start_link(name: :db, max_size: 2, max_uses: 3)
      {:ok, conn} = RecyclingPool.checkout(:db, 1_000)
      :ok = RecyclingPool.checkin(:db, conn)
  """

  use GenServer

  @default_max_size 10
  @default_min_size 0

  @typedoc "An opaque connection term produced by the `:create` function."
  @type conn :: term()

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:name, atom()}
          | {:max_size, pos_integer()}
          | {:min_size, non_neg_integer()}
          | {:max_uses, pos_integer() | :infinity}
          | {:create, (-> conn())}
          | {:destroy, (conn() -> any())}

  defmodule State do
    @moduledoc false

    defstruct max_size: 10,
              min_size: 0,
              max_uses: :infinity,
              create: nil,
              destroy: nil,
              available: [],
              uses: %{},
              checkouts: %{},
              waiters: :queue.new(),
              total: 0
  end

  # ---------------------------------------------------------------- public API

  @doc """
  Starts and links a pool.

  Options: `:name`, `:max_size` (default `10`), `:min_size` (default `0`),
  `:max_uses` (default `:infinity`), `:create` (default `fn -> make_ref() end`) and
  `:destroy` (default a no-op).

  Returns `{:error, reason}` when the options are invalid — for example when
  `min_size > max_size`, or `max_uses` is neither `:infinity` nor a positive integer.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if is_atom(name) and not is_nil(name), do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Borrows a connection from the pool, blocking up to `timeout` milliseconds.

  Returns `{:ok, conn}`, or `{:error, :timeout}` if no connection became available in
  time. A `timeout` of `0` never blocks.
  """
  @spec checkout(GenServer.server(), non_neg_integer()) :: {:ok, conn()} | {:error, :timeout}
  def checkout(name, timeout \\ 5_000) when is_integer(timeout) and timeout >= 0 do
    GenServer.call(name, {:checkout, timeout}, :infinity)
  end

  @doc """
  Returns a previously checked-out connection to the pool, completing one use.

  If the connection has reached `:max_uses` it is destroyed instead of being made
  available again. Always returns `:ok`.
  """
  @spec checkin(GenServer.server(), conn()) :: :ok
  def checkin(name, conn) do
    GenServer.call(name, {:checkin, conn})
  end

  @doc """
  Returns a snapshot of pool counters as
  `%{available: a, in_use: u, total: t, max: max, min: min, max_uses: max_uses}`,
  where `total == a + u`.
  """
  @spec stats(GenServer.server()) :: %{
          available: non_neg_integer(),
          in_use: non_neg_integer(),
          total: non_neg_integer(),
          max: pos_integer(),
          min: non_neg_integer(),
          max_uses: pos_integer() | :infinity
        }
  def stats(name) do
    GenServer.call(name, :stats)
  end

  @doc """
  Stops the pool, destroying every connection it still tracks.
  """
  @spec stop(GenServer.server(), term(), timeout()) :: :ok
  def stop(name, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(name, reason, timeout)
  end

  # ------------------------------------------------------------------ callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, max_size} <- validate_max_size(Keyword.get(opts, :max_size, @default_max_size)),
         {:ok, min_size} <- validate_min_size(Keyword.get(opts, :min_size, @default_min_size)),
         {:ok, max_uses} <- validate_max_uses(Keyword.get(opts, :max_uses, :infinity)),
         {:ok, create} <- validate_fun(Keyword.get(opts, :create, &default_create/0), 0, :create),
         {:ok, destroy} <-
           validate_fun(Keyword.get(opts, :destroy, &default_destroy/1), 1, :destroy),
         :ok <- validate_sizes(min_size, max_size) do
      state = %State{
        max_size: max_size,
        min_size: min_size,
        max_uses: max_uses,
        create: create,
        destroy: destroy
      }

      {:ok, prepopulate(state, min_size)}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:checkout, timeout}, from, state) do
    case take_available(state) do
      {:ok, conn, state} ->
        {:reply, {:ok, conn}, mark_checked_out(state, conn, from)}

      :empty when state.total < state.max_size ->
        conn = create_conn(state)
        state = %{state | total: state.total + 1, uses: Map.put(state.uses, conn, 0)}
        {:reply, {:ok, conn}, mark_checked_out(state, conn, from)}

      :empty when timeout == 0 ->
        {:reply, {:error, :timeout}, state}

      :empty ->
        {:noreply, enqueue_waiter(state, from, timeout)}
    end
  end

  def handle_call({:checkin, conn}, _from, state) do
    case Map.pop(state.checkouts, conn) do
      {nil, _} ->
        {:reply, :ok, state}

      {{_pid, monitor_ref}, checkouts} ->
        Process.demonitor(monitor_ref, [:flush])
        {:reply, :ok, complete_use(%{state | checkouts: checkouts}, conn)}
    end
  end

  def handle_call(:stats, _from, state) do
    available = length(state.available)

    stats = %{
      available: available,
      in_use: state.total - available,
      total: state.total,
      max: state.max_size,
      min: state.min_size,
      max_uses: state.max_uses
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:waiter_timeout, ref}, state) do
    case pull_waiter(state.waiters, ref) do
      {:ok, {_ref, from, _timer}, waiters} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | waiters: waiters}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case pop_checkout_by_ref(state.checkouts, monitor_ref) do
      {:ok, conn, checkouts} ->
        {:noreply, complete_use(%{state | checkouts: checkouts}, conn)}

      :error ->
        {:noreply, %{state | waiters: drop_waiter_by_monitor(state.waiters, monitor_ref)}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.keys(state.uses), fn conn -> safe_destroy(state, conn) end)
    :ok
  end

  # ------------------------------------------------------------------- internals

  # A use has completed for `conn` (check-in or owner crash): bump its count and either
  # retire it or make it available / hand it to the longest-waiting caller.
  defp complete_use(state, conn) do
    count = Map.get(state.uses, conn, 0) + 1

    if exhausted?(state.max_uses, count) do
      state = retire(state, conn)
      serve_waiter_with_fresh(state)
    else
      state = %{state | uses: Map.put(state.uses, conn, count)}
      hand_off(state, conn)
    end
  end

  defp exhausted?(:infinity, _count), do: false
  defp exhausted?(max_uses, count), do: count >= max_uses

  # Give `conn` to the longest-waiting caller, or park it as available.
  defp hand_off(state, conn) do
    case dequeue_waiter(state.waiters) do
      {:ok, {_ref, from, timer}, waiters} ->
        cancel_timer(timer)
        state = %{state | waiters: waiters}
        GenServer.reply(from, {:ok, conn})
        mark_checked_out(state, conn, from)

      :empty ->
        %{state | available: state.available ++ [conn]}
    end
  end

  # After a retirement there is spare capacity: if someone is waiting, create a fresh
  # connection for the longest-waiting caller.
  defp serve_waiter_with_fresh(state) do
    case dequeue_waiter(state.waiters) do
      {:ok, {_ref, from, timer}, waiters} ->
        cancel_timer(timer)
        conn = create_conn(state)

        state = %{
          state
          | waiters: waiters,
            total: state.total + 1,
            uses: Map.put(state.uses, conn, 0)
        }

        GenServer.reply(from, {:ok, conn})
        mark_checked_out(state, conn, from)

      :empty ->
        state
    end
  end

  defp retire(state, conn) do
    safe_destroy(state, conn)

    %{
      state
      | total: max(state.total - 1, 0),
        uses: Map.delete(state.uses, conn),
        available: List.delete(state.available, conn)
    }
  end

  defp take_available(%State{available: [conn | rest]} = state) do
    {:ok, conn, %{state | available: rest}}
  end

  defp take_available(%State{available: []}), do: :empty

  defp mark_checked_out(state, conn, {pid, _tag}) do
    monitor_ref = Process.monitor(pid)
    %{state | checkouts: Map.put(state.checkouts, conn, {pid, monitor_ref})}
  end

  defp enqueue_waiter(state, {pid, _tag} = from, timeout) do
    ref = make_ref()
    timer = Process.send_after(self(), {:waiter_timeout, ref}, timeout)
    monitor_ref = Process.monitor(pid)
    entry = {ref, from, timer, monitor_ref}
    %{state | waiters: :queue.in(entry, state.waiters)}
  end

  defp dequeue_waiter(waiters) do
    case :queue.out(waiters) do
      {{:value, {ref, from, timer, monitor_ref}}, rest} ->
        Process.demonitor(monitor_ref, [:flush])
        {:ok, {ref, from, timer}, rest}

      {:empty, _} ->
        :empty
    end
  end

  defp pull_waiter(waiters, ref) do
    list = :queue.to_list(waiters)

    case Enum.split_with(list, fn {r, _from, _timer, _mon} -> r == ref end) do
      {[{^ref, from, timer, monitor_ref}], rest} ->
        Process.demonitor(monitor_ref, [:flush])
        {:ok, {ref, from, timer}, :queue.from_list(rest)}

      {_, _} ->
        :error
    end
  end

  defp drop_waiter_by_monitor(waiters, monitor_ref) do
    waiters
    |> :queue.to_list()
    |> Enum.reject(fn {_ref, _from, timer, mon} ->
      if mon == monitor_ref do
        cancel_timer(timer)
        true
      else
        false
      end
    end)
    |> :queue.from_list()
  end

  defp pop_checkout_by_ref(checkouts, monitor_ref) do
    Enum.find_value(checkouts, :error, fn
      {conn, {_pid, ^monitor_ref}} -> {:ok, conn, Map.delete(checkouts, conn)}
      _other -> nil
    end)
  end

  defp prepopulate(state, 0), do: state

  defp prepopulate(state, count) do
    Enum.reduce(1..count, state, fn _i, acc ->
      conn = create_conn(acc)

      %{
        acc
        | available: acc.available ++ [conn],
          uses: Map.put(acc.uses, conn, 0),
          total: acc.total + 1
      }
    end)
  end

  defp create_conn(%State{create: create}), do: create.()

  defp safe_destroy(%State{destroy: destroy}, conn) do
    destroy.(conn)
    :ok
  catch
    _kind, _reason -> :ok
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp default_create, do: make_ref()

  defp default_destroy(_conn), do: :ok

  # ------------------------------------------------------------------ validation

  defp validate_max_size(size) when is_integer(size) and size > 0, do: {:ok, size}
  defp validate_max_size(other), do: {:error, {:invalid_max_size, other}}

  defp validate_min_size(size) when is_integer(size) and size >= 0, do: {:ok, size}
  defp validate_min_size(other), do: {:error, {:invalid_min_size, other}}

  defp validate_max_uses(:infinity), do: {:ok, :infinity}
  defp validate_max_uses(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp validate_max_uses(other), do: {:error, {:invalid_max_uses, other}}

  defp validate_fun(fun, arity, _key) when is_function(fun, arity), do: {:ok, fun}
  defp validate_fun(other, _arity, key), do: {:error, {:invalid_function, key, other}}

  defp validate_sizes(min_size, max_size) when min_size <= max_size, do: :ok
  defp validate_sizes(min_size, max_size), do: {:error, {:min_size_exceeds_max_size, min_size, max_size}}
end