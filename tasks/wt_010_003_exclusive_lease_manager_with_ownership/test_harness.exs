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
    :sys.get_state(mgr)

    state = :sys.get_state(mgr)
    assert map_size(state.leases) == 0
  end

  test "cleanup only removes expired leases, keeps active ones", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :old_resource, :alice)

    Clock.advance(900)
    {:ok, _} = LeaseManager.acquire(mgr, :new_resource, :bob)

    Clock.advance(101)

    send(mgr, :cleanup)
    :sys.get_state(mgr)

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
end
