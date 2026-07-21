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
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    Clock.advance(800)
    assert {:ok, new_expires} = LeaseManager.renew(mgr, :printer, :alice)
    assert new_expires == 1_800

    # At 1500ms (700ms since renew) — still active
    Clock.advance(700)
    assert {:ok, :alice, _} = LeaseManager.holder(mgr, :printer)

    # At 1801ms — expired
    Clock.advance(301)
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
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
