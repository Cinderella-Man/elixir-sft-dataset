# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule LeaseManager do
  @moduledoc """
  A GenServer that manages exclusive resource leases with automatic expiration.

  Each resource can have at most one active lease at a time, held by a
  specific owner. Only the owner may release or renew a lease. Expired
  leases are lazily cleaned up on access and proactively via a periodic sweep.

  ## Options

    * `:name`               - process registration name (optional)
    * `:lease_duration_ms`  - default lease duration in ms (default: 30_000 / 30 sec)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1
      min) — or `:infinity` to disable the automatic sweep
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
          cleanup_interval_ms: non_neg_integer() | :infinity,
          clock: (-> integer())
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LeaseManagerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      LeaseManager.start_link(
        clock: &Clock.now/0,
        lease_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{mgr: pid}
  end

  # -------------------------------------------------------
  # Basic acquire / release
  # -------------------------------------------------------

  test "acquire grants a lease on an available resource", %{mgr: mgr} do
    assert {:ok, lease_id} = LeaseManager.acquire(mgr, :printer, :alice)
    assert is_binary(lease_id)
  end

  test "acquire returns error when resource is already held", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :already_held, :alice} = LeaseManager.acquire(mgr, :printer, :bob)
  end

  test "acquire is not idempotent — same owner re-acquiring returns error", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :already_held, :alice} = LeaseManager.acquire(mgr, :printer, :alice)
  end

  test "release frees the resource for the owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert :ok = LeaseManager.release(mgr, :printer, :alice)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end

  test "release returns error for wrong owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :not_held} = LeaseManager.release(mgr, :printer, :bob)
  end

  test "release returns error for unknown resource", %{mgr: mgr} do
    assert {:error, :not_held} = LeaseManager.release(mgr, :scanner, :alice)
  end

  test "resource can be re-acquired after release", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)
    :ok = LeaseManager.release(mgr, :printer, :alice)

    assert {:ok, _} = LeaseManager.acquire(mgr, :printer, :bob)
  end

  # -------------------------------------------------------
  # Holder
  # -------------------------------------------------------

  test "holder returns owner and expiry for held resource", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:ok, :alice, expires_at} = LeaseManager.holder(mgr, :printer)
    assert expires_at == 1_000
  end

  test "holder returns :available for unknown resource", %{mgr: mgr} do
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end

  # -------------------------------------------------------
  # Lease expiration
  # -------------------------------------------------------

  test "lease expires after duration", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end

  test "lease is still active just before expiration", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(999)

    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)
  end

  test "expired lease allows another owner to acquire", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:ok, _} = LeaseManager.acquire(mgr, :printer, :bob)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :printer)
  end

  test "release of expired lease returns error", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :not_held} = LeaseManager.release(mgr, :printer, :alice)
  end

  # -------------------------------------------------------
  # Renew
  # -------------------------------------------------------

  test "renew extends lease from current time", %{mgr: mgr} do
    # TODO
  end

  test "renew returns error for wrong owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :not_held} = LeaseManager.renew(mgr, :printer, :bob)
  end

  test "renew returns error for expired lease", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(1_001)

    assert {:error, :not_held} = LeaseManager.renew(mgr, :printer, :alice)
  end

  test "renew returns error for unknown resource", %{mgr: mgr} do
    assert {:error, :not_held} = LeaseManager.renew(mgr, :scanner, :alice)
  end

  # -------------------------------------------------------
  # Force release
  # -------------------------------------------------------

  test "force_release removes lease regardless of owner", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert :ok = LeaseManager.force_release(mgr, :printer)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end

  test "force_release returns :ok for unknown resource", %{mgr: mgr} do
    assert :ok = LeaseManager.force_release(mgr, :printer)
  end

  # -------------------------------------------------------
  # Resource independence
  # -------------------------------------------------------

  test "leases on different resources are independent", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)
    {:ok, _} = LeaseManager.acquire(mgr, :scanner, :bob)

    LeaseManager.release(mgr, :printer, :alice)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :scanner)
  end

  test "expiring one resource does not affect another", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(500)
    {:ok, _} = LeaseManager.acquire(mgr, :scanner, :bob)

    Clock.advance(501)

    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :scanner)
  end

  # -------------------------------------------------------
  # Repeated renew keeps lease alive
  # -------------------------------------------------------

  test "repeated renews keep a lease alive indefinitely", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    for _ <- 1..5 do
      Clock.advance(800)
      assert {:ok, _} = LeaseManager.renew(mgr, :printer, :alice)
    end

    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired leases are cleaned up by sweep", %{mgr: mgr} do
    for i <- 1..100 do
      {:ok, _} = LeaseManager.acquire(mgr, "resource_#{i}", :owner)
    end

    Clock.advance(1_100)

    send(mgr, :cleanup)
    LeaseManager.holder(mgr, :barrier)

    # Every swept resource is free again, and can be leased by a new owner.
    for i <- 1..100 do
      assert {:error, :available} = LeaseManager.holder(mgr, "resource_#{i}")
      assert {:ok, _} = LeaseManager.acquire(mgr, "resource_#{i}", :next_owner)
    end
  end

  test "cleanup only removes expired leases, keeps active ones", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :old_resource, :alice)

    Clock.advance(900)
    {:ok, _} = LeaseManager.acquire(mgr, :new_resource, :bob)

    Clock.advance(101)

    send(mgr, :cleanup)
    LeaseManager.holder(mgr, :barrier)

    assert {:error, :available} = LeaseManager.holder(mgr, :old_resource)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :new_resource)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "lease with minimal duration (1ms)", %{mgr: _mgr} do
    {:ok, short} =
      LeaseManager.start_link(
        clock: &Clock.now/0,
        lease_duration_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, _} = LeaseManager.acquire(short, :resource, :alice)
    assert {:ok, :alice, _} = LeaseManager.holder(short, :resource)

    Clock.advance(2)
    assert {:error, :available} = LeaseManager.holder(short, :resource)
  end

  test "various resource and owner types", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, "string_resource", {:tuple, :owner})
    {:ok, _} = LeaseManager.acquire(mgr, 42, "string_owner")
    {:ok, _} = LeaseManager.acquire(mgr, {:complex, :key}, :atom_owner)

    assert {:ok, {:tuple, :owner}, _} = LeaseManager.holder(mgr, "string_resource")
    assert {:ok, "string_owner", _} = LeaseManager.holder(mgr, 42)
    assert {:ok, :atom_owner, _} = LeaseManager.holder(mgr, {:complex, :key})
  end

  test "acquire uses default 30000ms lease duration when unspecified", %{mgr: _mgr} do
    {:ok, dflt} =
      LeaseManager.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, _} = LeaseManager.acquire(dflt, :printer, :alice)
    assert {:ok, :alice, 30_000} = LeaseManager.holder(dflt, :printer)

    Clock.advance(30_000)
    assert {:error, :available} = LeaseManager.holder(dflt, :printer)
  end

  test "server is reachable through the registered :name option", %{mgr: _mgr} do
    name = :lease_manager_named_test

    {:ok, _} =
      LeaseManager.start_link(
        name: name,
        clock: &Clock.now/0,
        lease_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, _} = LeaseManager.acquire(name, :printer, :alice)
    assert {:ok, :alice, _} = LeaseManager.holder(name, :printer)
  end

  test "lease ids are unpadded url-safe base64 of 16 random bytes", %{mgr: mgr} do
    {:ok, id1} = LeaseManager.acquire(mgr, :printer, :alice)
    {:ok, id2} = LeaseManager.acquire(mgr, :scanner, :bob)

    assert String.length(id1) == 22
    assert id1 =~ ~r/\A[A-Za-z0-9_-]{22}\z/
    refute String.contains?(id1, "=")
    assert id1 != id2
  end

  # -------------------------------------------------------
  # Automatic periodic sweep (finite :cleanup_interval_ms)
  # -------------------------------------------------------

  # With a finite interval the sweep must run on its own, without anything
  # poking the server. A sweep is told apart from lazy cleanup-on-access by
  # rewinding the clock before looking: a lease that was merely left in place
  # is live again once the clock sits before its expiry, so observing
  # `{:error, :available}` at the rewound time means the lease was genuinely
  # removed while the clock was ahead of expiry — i.e. by the sweep.
  test "sweep runs automatically on a finite interval and keeps re-arming", %{mgr: _mgr} do
    {:ok, sweeper} =
      LeaseManager.start_link(
        clock: &Clock.now/0,
        lease_duration_ms: 1_000,
        cleanup_interval_ms: 25
      )

    on_exit(fn ->
      try do
        GenServer.stop(sweeper)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, _} = LeaseManager.acquire(sweeper, :printer, :alice)

    # Leave the clock past expiry so an automatic pass sees an expired lease.
    Clock.set(10_000)
    assert await_swept(sweeper, :printer, 500, 10_000, 1_000)

    # A second lease, expired later, is swept as well: the timer is periodic
    # rather than a single one-shot pass.
    Clock.set(20_000)
    {:ok, _} = LeaseManager.acquire(sweeper, :printer, :bob)

    Clock.set(30_000)
    assert await_swept(sweeper, :printer, 20_500, 30_000, 1_000)
  end

  # Polls until the resource is observed as removed, or the budget runs out.
  defp await_swept(server, resource, live_time, expired_time, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    Clock.set(expired_time)
    poll_swept(server, resource, live_time, expired_time, deadline)
  end

  defp poll_swept(server, resource, live_time, expired_time, deadline) do
    Clock.set(live_time)
    observed = LeaseManager.holder(server, resource)
    Clock.set(expired_time)

    cond do
      match?({:error, :available}, observed) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(5)
        poll_swept(server, resource, live_time, expired_time, deadline)
    end
  end
end
```
