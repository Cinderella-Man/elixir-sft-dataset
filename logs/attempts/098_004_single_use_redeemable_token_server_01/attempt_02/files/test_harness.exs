defmodule SingleUseTokenTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic expiry testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &(&1 + seconds))
    def set(seconds), do: Agent.update(__MODULE__, fn _ -> seconds end)
  end

  setup do
    start_supervised!({Clock, 1_000_000})
    server = start_supervised!({SingleUseToken, secret: "s3cr3t", clock: &Clock.now/0})
    %{server: server}
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "issued token redeems successfully", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, %{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = SingleUseToken.redeem(s, token)
  end

  test "payload is preserved exactly through round-trip", %{server: s} do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    {:ok, token} = SingleUseToken.issue(s, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(s, token)
  end

  test "token is URL-safe (no +, /, or = characters)", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "issuing the same payload twice yields different tokens", %{server: s} do
    {:ok, t1} = SingleUseToken.issue(s, "same", 60)
    {:ok, t2} = SingleUseToken.issue(s, "same", 60)
    refute t1 == t2
    assert {:ok, "same"} = SingleUseToken.redeem(s, t1)
    assert {:ok, "same"} = SingleUseToken.redeem(s, t2)
  end

  # -------------------------------------------------------
  # Single-use semantics
  # -------------------------------------------------------

  test "second redemption of the same token returns :already_redeemed", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "once", 300)
    assert {:ok, "once"} = SingleUseToken.redeem(s, token)
    assert {:error, :already_redeemed} = SingleUseToken.redeem(s, token)
  end

  test "a failed redemption does not consume the token", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "keep", 100)
    Clock.advance(200)
    # Expired: fails, must not be recorded as used.
    assert {:error, :expired} = SingleUseToken.redeem(s, token)
    # Move time back before expiry; the token is still redeemable.
    Clock.set(1_000_000)
    assert {:ok, "keep"} = SingleUseToken.redeem(s, token)
  end

  test "ledger is per-server: a shared-secret token redeems once on each server", %{server: s} do
    other =
      start_supervised!({SingleUseToken, secret: "s3cr3t", clock: &Clock.now/0}, id: :server_b)

    {:ok, token} = SingleUseToken.issue(s, "shared", 300)
    assert {:ok, "shared"} = SingleUseToken.redeem(s, token)
    # The other server has never seen it; same secret means it verifies there.
    assert {:ok, "shared"} = SingleUseToken.redeem(other, token)
    # But it is single-use on that server too.
    assert {:error, :already_redeemed} = SingleUseToken.redeem(other, token)
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = SingleUseToken.redeem(s, token)
  end

  test "expired token returns :expired", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(s, token)
  end

  test "token expires exactly at ttl boundary", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = SingleUseToken.redeem(s, token)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "wrong secret returns :invalid_signature", %{server: s} do
    other =
      start_supervised!({SingleUseToken, secret: "different", clock: &Clock.now/0}, id: :server_c)

    {:ok, token} = SingleUseToken.issue(s, "payload", 300)
    assert {:error, :invalid_signature} = SingleUseToken.redeem(other, token)
  end

  test "tampered token returns :invalid_signature", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = SingleUseToken.redeem(s, tampered)
  end

  test "signature check takes precedence over expiry check", %{server: s} do
    other =
      start_supervised!({SingleUseToken, secret: "different", clock: &Clock.now/0}, id: :server_d)

    {:ok, token} = SingleUseToken.issue(s, "old", 1)
    Clock.advance(200)
    assert {:error, :invalid_signature} = SingleUseToken.redeem(other, token)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed", %{server: s} do
    assert {:error, :malformed} = SingleUseToken.redeem(s, "")
  end

  test "random binary returns :malformed", %{server: s} do
    assert {:error, :malformed} = SingleUseToken.redeem(s, "notavalidtoken!!!")
  end

  test "truncated token returns :malformed", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, "hello", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 3))
    assert {:error, :malformed} = SingleUseToken.redeem(s, truncated)
  end

  test "valid base64 but garbage content returns :malformed", %{server: s} do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = SingleUseToken.redeem(s, garbage)
  end

  test "non-binary token returns :malformed", %{server: s} do
    assert {:error, :malformed} = SingleUseToken.redeem(s, 12345)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, :hello, 60)
    assert {:ok, :hello} = SingleUseToken.redeem(s, token)
  end

  test "supports integer payload", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, 12345, 60)
    assert {:ok, 12345} = SingleUseToken.redeem(s, token)
  end

  test "supports list payload", %{server: s} do
    {:ok, token} = SingleUseToken.issue(s, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = SingleUseToken.redeem(s, token)
  end

  test "supports deeply nested map payload", %{server: s} do
    payload = %{a: %{b: %{c: "deep"}}}
    {:ok, token} = SingleUseToken.issue(s, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(s, token)
  end
end
