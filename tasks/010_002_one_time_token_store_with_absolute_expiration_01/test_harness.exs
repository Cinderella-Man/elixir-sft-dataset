defmodule OneTimeTokenStoreTest do
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
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        default_ttl_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{store: pid}
  end

  # -------------------------------------------------------
  # Basic mint / verify / redeem
  # -------------------------------------------------------

  test "mint returns a unique token id", %{store: store} do
    assert {:ok, id1} = OneTimeTokenStore.mint(store, %{action: :reset})
    assert {:ok, id2} = OneTimeTokenStore.mint(store, %{action: :invite})

    assert is_binary(id1)
    assert is_binary(id2)
    assert id1 != id2
  end

  test "verify retrieves the token payload without consuming it", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice", action: :reset})

    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
    # Still available after verify
    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
  end

  test "verify returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, "nonexistent")
  end

  test "redeem returns payload and removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.redeem(store, id)
    # Second redeem fails — token is consumed
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "redeem returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, "nonexistent")
  end

  test "verify fails after redeem", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "ABC"})

    assert {:ok, _} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end

  # -------------------------------------------------------
  # Revoke
  # -------------------------------------------------------

  test "revoke removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "revoke returns :ok for unknown token", %{store: store} do
    assert :ok = OneTimeTokenStore.revoke(store, "nonexistent")
  end

  # -------------------------------------------------------
  # Absolute expiration (NOT sliding)
  # -------------------------------------------------------

  test "token expires after its TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "token is still alive just before TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(999)

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.verify(store, id)
  end

  test "verify does NOT extend the expiration (absolute, not sliding)", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    # Verify at 800ms — still alive
    Clock.advance(800)
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    # Another 300ms later (total 1100ms from creation) — expired
    # In a sliding-window store, the verify at 800ms would have extended it.
    # Here it must NOT extend.
    Clock.advance(300)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end

  # -------------------------------------------------------
  # Per-token TTL override
  # -------------------------------------------------------

  test "mint accepts per-token :ttl_ms override", %{store: store} do
    {:ok, short_id} = OneTimeTokenStore.mint(store, %{type: :short}, ttl_ms: 200)
    {:ok, long_id} = OneTimeTokenStore.mint(store, %{type: :long}, ttl_ms: 5_000)

    Clock.advance(300)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, short_id)
    assert {:ok, %{type: :long}} = OneTimeTokenStore.verify(store, long_id)
  end

  # -------------------------------------------------------
  # Token independence
  # -------------------------------------------------------

  test "tokens are fully independent", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(500)
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    # At time 1001: alice expired, bob still has ~500ms
    Clock.advance(501)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end

  test "redeeming one token does not affect another", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    OneTimeTokenStore.redeem(store, id_a)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end

  # -------------------------------------------------------
  # active_count
  # -------------------------------------------------------

  test "active_count reflects only non-expired, non-redeemed tokens", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, %{n: 1})
    {:ok, _id2} = OneTimeTokenStore.mint(store, %{n: 2})
    {:ok, _id3} = OneTimeTokenStore.mint(store, %{n: 3})

    assert OneTimeTokenStore.active_count(store) == 3

    # Redeem one
    OneTimeTokenStore.redeem(store, id1)
    assert OneTimeTokenStore.active_count(store) == 2

    # Expire the remaining two
    Clock.advance(1_001)
    assert OneTimeTokenStore.active_count(store) == 0
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired tokens are cleaned up by sweep", %{store: store} do
    ids =
      for i <- 1..100 do
        {:ok, id} = OneTimeTokenStore.mint(store, %{index: i})
        id
      end

    Clock.advance(1_100)

    send(store, :cleanup)
    :sys.get_state(store)

    state = :sys.get_state(store)
    assert map_size(state.tokens) == 0

    for id <- ids do
      assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    end
  end

  test "cleanup only removes expired tokens, keeps active ones", %{store: store} do
    {:ok, old_id} = OneTimeTokenStore.mint(store, %{user: "old"})

    Clock.advance(900)
    {:ok, new_id} = OneTimeTokenStore.mint(store, %{user: "new"})

    Clock.advance(101)

    send(store, :cleanup)
    :sys.get_state(store)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, old_id)
    assert {:ok, %{user: "new"}} = OneTimeTokenStore.verify(store, new_id)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "token with minimal TTL (1ms)", %{store: _store} do
    {:ok, short} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        default_ttl_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(short, %{flash: true})
    assert {:ok, _} = OneTimeTokenStore.verify(short, id)

    Clock.advance(2)
    assert {:error, :not_found} = OneTimeTokenStore.verify(short, id)
  end

  test "mint works with various payload types", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, "just a string")
    {:ok, id2} = OneTimeTokenStore.mint(store, [1, 2, 3])
    {:ok, id3} = OneTimeTokenStore.mint(store, {:tuple, :data})

    assert {:ok, "just a string"} = OneTimeTokenStore.redeem(store, id1)
    assert {:ok, [1, 2, 3]} = OneTimeTokenStore.redeem(store, id2)
    assert {:ok, {:tuple, :data}} = OneTimeTokenStore.redeem(store, id3)
  end

  test "double-redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{one_shot: true})

    assert {:ok, %{one_shot: true}} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "revoke then redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "XYZ"})

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end
end
