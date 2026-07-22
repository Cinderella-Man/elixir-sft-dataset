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
end
