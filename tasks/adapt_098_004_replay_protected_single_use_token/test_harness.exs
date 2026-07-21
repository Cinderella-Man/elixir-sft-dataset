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

    server =
      start_supervised!({SingleUseToken, secret: "server-secret", clock: &Clock.now/0})

    %{server: server}
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "issued token redeems successfully", %{server: server} do
    token = SingleUseToken.issue(server, %{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = SingleUseToken.redeem(server, token)
  end

  test "payload is preserved exactly through round-trip", %{server: server} do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end

  test "token is URL-safe (no +, /, or = characters)", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Single use / replay
  # -------------------------------------------------------

  test "a token can be redeemed only once; the second redemption is :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "once", 300)
    assert {:ok, "once"} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "consuming one token does not consume an independently issued token",
       %{server: server} do
    t1 = SingleUseToken.issue(server, "a", 300)
    t2 = SingleUseToken.issue(server, "b", 300)

    assert {:ok, "a"} = SingleUseToken.redeem(server, t1)
    # t2 is unaffected by t1's redemption.
    assert {:ok, "b"} = SingleUseToken.redeem(server, t2)
  end

  test "replay check takes precedence over expiry", %{server: server} do
    token = SingleUseToken.issue(server, "x", 100)
    assert {:ok, "x"} = SingleUseToken.redeem(server, token)

    # Advance past the token's expiry; a consumed token stays :replayed.
    Clock.advance(500)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Nonce independence for identical issuance arguments
  # -------------------------------------------------------

  test "two tokens issued with the same payload and ttl are different binaries",
       %{server: server} do
    # Each call mints a fresh random nonce, so identical arguments still yield
    # distinct tokens even though the clock is frozen.
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    refute t1 == t2
  end

  test "redeeming a token does not consume another token with the identical payload",
       %{server: server} do
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t1)
    # Distinct nonces: t1's redemption leaves t2 fully redeemable.
    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t2)

    # Each token is now individually consumed.
    assert {:error, :replayed} = SingleUseToken.redeem(server, t1)
    assert {:error, :replayed} = SingleUseToken.redeem(server, t2)
  end

  # -------------------------------------------------------
  # Default clock (`:clock` omitted)
  # -------------------------------------------------------

  test "server started without :clock issues and redeems tokens" do
    server =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: "default-clock-secret"},
          id: :default_clock_server
        )
      )

    token = SingleUseToken.issue(server, %{user_id: 3}, 300)
    assert {:ok, %{user_id: 3}} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "the omitted :clock defaults to Unix epoch seconds" do
    secret = "epoch-secret"
    now = System.os_time(:second)

    # Issues on the default clock; the two peers share the secret, so the tokens
    # verify there and are judged against a known epoch-second time.
    issuer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret}, id: :epoch_issuer)
      )

    present_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now end},
          id: :epoch_present_peer
        )
      )

    future_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now + 3_600 end},
          id: :epoch_future_peer
        )
      )

    # A 60-second token issued "now" is still valid at epoch second `now` ...
    assert {:ok, "epoch"} =
             SingleUseToken.redeem(present_peer, SingleUseToken.issue(issuer, "epoch", 60))

    # ... and expired an hour later, which only holds if the default clock ticks
    # in epoch seconds rather than some other unit or epoch.
    assert {:error, :expired} =
             SingleUseToken.redeem(future_peer, SingleUseToken.issue(issuer, "epoch", 60))
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry", %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = SingleUseToken.redeem(server, token)
  end

  test "expired, never-consumed token returns :expired", %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end

  test "token expires exactly at ttl boundary", %{server: server} do
    token = SingleUseToken.issue(server, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end

  test "an expired token is not consumed, so it never becomes :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
    # Still :expired, not :replayed — the failed redemption consumed nothing.
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "a token issued by another server (different secret) is :invalid_signature",
       %{server: server} do
    other =
      start_supervised!(
        Supervisor.child_spec(
          {SingleUseToken, secret: "different-secret", clock: &Clock.now/0},
          id: :other_server
        )
      )

    token = SingleUseToken.issue(server, "x", 300)
    assert {:error, :invalid_signature} = SingleUseToken.redeem(other, token)
  end

  test "tampered token returns :invalid_signature", %{server: server} do
    token = SingleUseToken.issue(server, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = SingleUseToken.redeem(server, tampered)
  end

  test "no byte of the signed region can be rewritten without rejection",
       %{server: server} do
    # The signed region is everything ahead of the trailing 32-byte MAC: the
    # nonce, the issue and expiry timestamps, any length prefix and the payload
    # bytes. Rewriting any one of those bytes must be caught either by the
    # structural parse (:malformed) or by HMAC verification
    # (:invalid_signature) — and, because HMAC verification runs before the
    # expiry check, never by expiry and never by acceptance. In particular a
    # rewritten expiry timestamp cannot buy an attacker extra lifetime.
    token = SingleUseToken.issue(server, %{role: "user"}, 100)
    {:ok, raw} = Base.url_decode64(token, padding: false)
    signed_size = byte_size(raw) - 32
    assert signed_size > 0

    for index <- 0..(signed_size - 1), value <- rewrites(:binary.at(raw, index)) do
      mutated = Base.url_encode64(put_byte(raw, index, value), padding: false)
      assert {:error, reason} = SingleUseToken.redeem(server, mutated)
      assert reason in [:malformed, :invalid_signature]
    end

    # None of those rejected redemptions consumed anything, so the pristine
    # token is still redeemable exactly once.
    assert {:ok, %{role: "user"}} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "no byte of the trailing MAC can be rewritten without rejection",
       %{server: server} do
    # Rewriting a MAC byte leaves the header consistent with the remaining
    # bytes, so the structure still parses cleanly and the failure is
    # attributed to the signature rather than to decoding.
    token = SingleUseToken.issue(server, %{role: "user"}, 100)
    {:ok, raw} = Base.url_decode64(token, padding: false)
    signed_size = byte_size(raw) - 32
    assert signed_size > 0

    for index <- signed_size..(byte_size(raw) - 1), value <- rewrites(:binary.at(raw, index)) do
      mutated = Base.url_encode64(put_byte(raw, index, value), padding: false)
      assert {:error, :invalid_signature} = SingleUseToken.redeem(server, mutated)
    end

    assert {:ok, %{role: "user"}} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "")
  end

  test "random binary returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "notavalidtoken!!!")
  end

  test "truncated token returns :malformed", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = SingleUseToken.redeem(server, truncated)
  end

  test "valid base64 but garbage content returns :malformed", %{server: server} do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = SingleUseToken.redeem(server, garbage)
  end

  test "non-binary token input returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, 12345)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload", %{server: server} do
    token = SingleUseToken.issue(server, :hello, 60)
    assert {:ok, :hello} = SingleUseToken.redeem(server, token)
  end

  test "supports integer payload", %{server: server} do
    token = SingleUseToken.issue(server, 12345, 60)
    assert {:ok, 12345} = SingleUseToken.redeem(server, token)
  end

  test "supports list payload", %{server: server} do
    token = SingleUseToken.issue(server, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = SingleUseToken.redeem(server, token)
  end

  test "supports deeply nested map payload", %{server: server} do
    payload = %{a: %{b: %{c: "deep"}}}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end

  # --- Byte-rewriting helpers ---

  # Replacement values for one byte, chosen so that whichever way a timestamp
  # field is laid out, at least one rewrite pushes it far into the future while
  # others clear or invert it. Values equal to the original byte are dropped so
  # every rewrite really changes the token.
  defp rewrites(byte) do
    [:erlang.bxor(byte, 0xFF), 0x00, 0x7F, 0xFF]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == byte))
  end

  defp put_byte(raw, index, value) do
    <<prefix::binary-size(^index), _old, rest::binary>> = raw
    prefix <> <<value>> <> rest
  end
end
