defmodule TOTPVaultTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = TOTPVault.start_link()
    %{vault: pid}
  end

  # -------------------------------------------------------------------
  # register / secret
  # -------------------------------------------------------------------

  test "register returns a base32 secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end

  test "register is idempotent-guarded: second call errors and keeps the secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert {:error, :already_registered} = TOTPVault.register(v, "alice")
    assert {:ok, ^secret} = TOTPVault.secret(v, "alice")
  end

  test "secret returns :not_found for an unknown account", %{vault: v} do
    assert {:error, :not_found} = TOTPVault.secret(v, "nobody")
  end

  test "different accounts get different secrets", %{vault: v} do
    {:ok, a} = TOTPVault.register(v, "alice")
    {:ok, b} = TOTPVault.register(v, "bob")
    refute a == b
  end

  # -------------------------------------------------------------------
  # current_code
  # -------------------------------------------------------------------

  test "current_code is read-only and stable within a step", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_029)
    assert c1 == c2
    assert byte_size(c1) == 6
    # Still consumable afterward — reading did not spend it.
    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
  end

  test "current_code returns :not_found for unknown account", %{vault: v} do
    assert {:error, :not_found} = TOTPVault.current_code(v, "ghost", time: 1)
  end

  # -------------------------------------------------------------------
  # consume — basic acceptance / rejection
  # -------------------------------------------------------------------

  test "consume accepts the current code once", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)
    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok
  end

  test "consume rejects a wrong code as :invalid", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    wrong =
      code
      |> String.to_integer()
      |> then(&rem(&1 + 1, 1_000_000))
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    assert TOTPVault.consume(v, "alice", wrong, time: 90_000) == {:error, :invalid}
  end

  test "consume accepts an integer code", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)
    assert TOTPVault.consume(v, "alice", String.to_integer(code), time: 90_000) == :ok
  end

  test "consume returns :not_found for an unknown account", %{vault: v} do
    assert TOTPVault.consume(v, "ghost", "123456", time: 90_000) == {:error, :not_found}
  end

  # -------------------------------------------------------------------
  # consume — replay protection
  # -------------------------------------------------------------------

  test "re-consuming the same code returns :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, code} = TOTPVault.current_code(v, "alice", time: 90_000)

    assert TOTPVault.consume(v, "alice", code, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", code, time: 90_000) == {:error, :replayed}
  end

  test "after consuming the current step, an earlier step's code is :replayed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, current} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)

    assert TOTPVault.consume(v, "alice", current, time: 90_000) == :ok
    # prev belongs to step base-1 <= last consumed step base.
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == {:error, :replayed}
  end

  test "a drifted (previous-step) code is accepted when not yet consumed", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, prev} = TOTPVault.current_code(v, "alice", time: 90_000 - 30)
    # window default 1 covers base-1
    assert TOTPVault.consume(v, "alice", prev, time: 90_000) == :ok
  end

  test "a later step's code still works after an earlier consumption", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    {:ok, c1} = TOTPVault.current_code(v, "alice", time: 90_000)
    {:ok, c2} = TOTPVault.current_code(v, "alice", time: 90_030)

    assert TOTPVault.consume(v, "alice", c1, time: 90_000) == :ok
    assert TOTPVault.consume(v, "alice", c2, time: 90_030) == :ok
  end

  # -------------------------------------------------------------------
  # concurrency — exactly one winner
  # -------------------------------------------------------------------

  test "concurrent consumption of the same code yields exactly one :ok", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    t = 90_000
    {:ok, code} = TOTPVault.current_code(v, "alice", time: t)

    results =
      1..25
      |> Task.async_stream(fn _ -> TOTPVault.consume(v, "alice", code, time: t) end,
        max_concurrency: 25
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :replayed})) == 24
  end
end
