defmodule RevocableTokenTest do
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

  defp start_server(secret, id) do
    spec =
      Supervisor.child_spec(
        {RevocableToken, [secret: secret, clock: &Clock.now/0]},
        id: id
      )

    start_supervised!(spec)
  end

  setup do
    start_supervised!({Clock, 1_000_000})
    server = start_server("top-secret", :primary)
    {:ok, server: server}
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "issued token verifies successfully", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, %{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = RevocableToken.verify(server, token)
  end

  test "payload is preserved exactly through round-trip", %{server: server} do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    {:ok, token} = RevocableToken.issue(server, payload, 60)
    assert {:ok, ^payload} = RevocableToken.verify(server, token)
  end

  test "token is URL-safe (no +, /, or = characters)", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "issuing the same payload twice yields different tokens", %{server: server} do
    {:ok, t1} = RevocableToken.issue(server, %{a: 1}, 300)
    {:ok, t2} = RevocableToken.issue(server, %{a: 1}, 300)
    assert t1 != t2
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = RevocableToken.verify(server, token)
  end

  test "expired token returns :expired", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = RevocableToken.verify(server, token)
  end

  test "token expires exactly at ttl boundary", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = RevocableToken.verify(server, token)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "token from a server with a different secret is :invalid_signature", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "msg", 300)
    other = start_server("different-secret", :other_sig)
    assert {:error, :invalid_signature} = RevocableToken.verify(other, token)
  end

  test "tampered payload returns :invalid_signature", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = RevocableToken.verify(server, tampered)
  end

  test "signature is checked before revocation status", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "x", 300)
    other = start_server("another-secret", :other_precedence)
    :ok = RevocableToken.revoke(other, token)
    # Revoked on `other`, but its signature does not verify there → signature wins.
    assert {:error, :invalid_signature} = RevocableToken.verify(other, token)
  end

  # -------------------------------------------------------
  # Revocation
  # -------------------------------------------------------

  test "revoked token returns :revoked", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "x", 300)
    assert {:ok, "x"} = RevocableToken.verify(server, token)
    assert :ok = RevocableToken.revoke(server, token)
    assert {:error, :revoked} = RevocableToken.verify(server, token)
  end

  test "verify is read-only and revocation status is stable", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "x", 300)
    :ok = RevocableToken.revoke(server, token)
    assert {:error, :revoked} = RevocableToken.verify(server, token)
    assert {:error, :revoked} = RevocableToken.verify(server, token)
  end

  test "revoking one token does not affect another", %{server: server} do
    {:ok, t1} = RevocableToken.issue(server, "a", 300)
    {:ok, t2} = RevocableToken.issue(server, "b", 300)
    :ok = RevocableToken.revoke(server, t1)
    assert {:error, :revoked} = RevocableToken.verify(server, t1)
    assert {:ok, "b"} = RevocableToken.verify(server, t2)
  end

  test "revocation takes precedence over expiry", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "x", 10)
    :ok = RevocableToken.revoke(server, token)
    Clock.advance(1000)
    assert {:error, :revoked} = RevocableToken.verify(server, token)
  end

  test "revocation is per-server", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "x", 300)
    :ok = RevocableToken.revoke(server, token)
    # A second server sharing the same secret has its own revocation set.
    other = start_server("top-secret", :other_server)
    assert {:ok, "x"} = RevocableToken.verify(other, token)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed", %{server: server} do
    assert {:error, :malformed} = RevocableToken.verify(server, "")
  end

  test "random binary returns :malformed", %{server: server} do
    assert {:error, :malformed} = RevocableToken.verify(server, "notavalidtoken!!!")
  end

  test "truncated token returns :malformed", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, "hello", 60)
    truncated = binary_part(token, 0, 10)
    assert {:error, :malformed} = RevocableToken.verify(server, truncated)
  end

  test "valid base64 but garbage content returns :malformed", %{server: server} do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = RevocableToken.verify(server, garbage)
  end

  test "non-binary input returns :malformed", %{server: server} do
    assert {:error, :malformed} = RevocableToken.verify(server, 12345)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, :hello, 60)
    assert {:ok, :hello} = RevocableToken.verify(server, token)
  end

  test "supports integer payload", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, 12345, 60)
    assert {:ok, 12345} = RevocableToken.verify(server, token)
  end

  test "supports list payload", %{server: server} do
    {:ok, token} = RevocableToken.issue(server, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = RevocableToken.verify(server, token)
  end

  test "supports deeply nested map payload", %{server: server} do
    payload = %{a: %{b: %{c: "deep"}}}
    {:ok, token} = RevocableToken.issue(server, payload, 60)
    assert {:ok, ^payload} = RevocableToken.verify(server, token)
  end
end
