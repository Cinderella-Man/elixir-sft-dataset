defmodule LeaseManager do
  @moduledoc """
  A GenServer that manages exclusive resource leases with automatic expiration.

  Each resource can have at most one active lease at a time, held by a
  specific owner. Only the owner may release or renew a lease. Expired
  leases are lazily cleaned up on access and proactively via a periodic sweep.

  ## Options

    * `:name`               - process registration name (optional)
    * `:lease_duration_ms`  - default lease duration in ms (default: 30_000 / 30 sec)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = LeaseManager.start_link(lease_duration_ms: 5_000)

      {:ok, lease_id} = LeaseManager.acquire(pid, :printer, :alice)
      {:error, :already_held, :alice} = LeaseManager.acquire(pid, :printer, :bob)

      {:ok, _} = LeaseManager.renew(pid, :printer, :alice)
      :ok = LeaseManager.release(pid, :printer, :alice)

      {:ok, _lease_id2} = LeaseManager.acquire(pid, :printer, :bob)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type resource :: term()
  @type owner :: term()
  @type lease_id :: String.t()

  @type lease :: %{
          lease_id: lease_id(),
          owner: owner(),
          expires_at: integer()
        }

  @type state :: %{
          leases: %{resource() => lease()},
          lease_duration_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (() -> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_lease_duration_ms 30_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `LeaseManager` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:lease_duration_ms`   - default lease duration (default #{@default_lease_duration_ms} ms)
    * `:cleanup_interval_ms` - sweep interval (default #{@default_cleanup_interval_ms} ms)
    * `:clock`               - zero-arity fn returning current time in ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  @doc """
  Attempts to acquire an exclusive lease on `resource` for `owner`.

  Returns `{:ok, lease_id}` if the resource is available (or its previous
  lease has expired), or `{:error, :already_held, current_owner}` if another
  owner holds a valid lease.
  """
  @spec acquire(server(), resource(), owner()) ::
          {:ok, lease_id()} | {:error, :already_held, owner()}
  def acquire(server, resource, owner) do
    GenServer.call(server, {:acquire, resource, owner})
  end

  @doc """
  Releases a lease on `resource`. Only the current owner may release it.

  Returns `:ok` on success, or `{:error, :not_held}` if the lease doesn't
  exist, has expired, or is held by a different owner.
  """
  @spec release(server(), resource(), owner()) :: :ok | {:error, :not_held}
  def release(server, resource, owner) do
    GenServer.call(server, {:release, resource, owner})
  end

  @doc """
  Extends the lease on `resource` for another full duration from the current time.

  Returns `{:ok, new_expires_at}` on success, or `{:error, :not_held}` if
  the lease doesn't exist, has expired, or is held by a different owner.
  """
  @spec renew(server(), resource(), owner()) ::
          {:ok, integer()} | {:error, :not_held}
  def renew(server, resource, owner) do
    GenServer.call(server, {:renew, resource, owner})
  end

  @doc """
  Returns `{:ok, owner, expires_at}` if `resource` has a valid lease, or
  `{:error, :available}` if the resource is available.
  """
  @spec holder(server(), resource()) ::
          {:ok, owner(), integer()} | {:error, :available}
  def holder(server, resource) do
    GenServer.call(server, {:holder, resource})
  end

  @doc """
  Unconditionally removes any lease on `resource` regardless of owner.

  Always returns `:ok`. This is an administrative operation.
  """
  @spec force_release(server(), resource()) :: :ok
  def force_release(server, resource) do
    GenServer.call(server, {:force_release, resource})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    lease_duration_ms = Keyword.get(opts, :lease_duration_ms, @default_lease_duration_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      leases: %{},
      lease_duration_ms: lease_duration_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:acquire, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} ->
        {:reply, {:error, :already_held, lease.owner}, state}

      :expired ->
        lease_id = generate_lease_id()
        new_lease = %{lease_id: lease_id, owner: owner, expires_at: now + state.lease_duration_ms}
        new_leases = Map.put(state.leases, resource, new_lease)
        {:reply, {:ok, lease_id}, %{state | leases: new_leases}}

      :missing ->
        lease_id = generate_lease_id()
        new_lease = %{lease_id: lease_id, owner: owner, expires_at: now + state.lease_duration_ms}
        new_leases = Map.put(state.leases, resource, new_lease)
        {:reply, {:ok, lease_id}, %{state | leases: new_leases}}
    end
  end

  def handle_call({:release, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} when lease.owner == owner ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, :ok, %{state | leases: new_leases}}

      {:ok, _lease} ->
        {:reply, {:error, :not_held}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :not_held}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call({:renew, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} when lease.owner == owner ->
        new_expires_at = now + state.lease_duration_ms
        updated_lease = %{lease | expires_at: new_expires_at}
        new_leases = Map.put(state.leases, resource, updated_lease)
        {:reply, {:ok, new_expires_at}, %{state | leases: new_leases}}

      {:ok, _lease} ->
        {:reply, {:error, :not_held}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :not_held}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call({:holder, resource}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} ->
        {:reply, {:ok, lease.owner, lease.expires_at}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :available}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :available}, state}
    end
  end

  def handle_call({:force_release, resource}, _from, state) do
    new_leases = Map.delete(state.leases, resource)
    {:reply, :ok, %{state | leases: new_leases}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_leases =
      Map.filter(state.leases, fn {_resource, lease} ->
        not expired?(lease, now)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | leases: surviving_leases}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec generate_lease_id() :: lease_id()
  defp generate_lease_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  @spec expired?(lease(), integer()) :: boolean()
  defp expired?(lease, now) do
    now >= lease.expires_at
  end

  @spec fetch_live_lease(%{resource() => lease()}, resource(), integer()) ::
          {:ok, lease()} | :expired | :missing
  defp fetch_live_lease(leases, resource, now) do
    case Map.fetch(leases, resource) do
      {:ok, lease} ->
        if expired?(lease, now), do: :expired, else: {:ok, lease}

      :error ->
        :missing
    end
  end
end
