defmodule TokenAuthorityTest do
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
    :ok
  end

  # Each test starts its own authority (with a unique supervisor child id so
  # several can coexist under the test supervisor). The authority reads time
  # through our fake clock; in production it falls back to System.os_time.
  defp start_authority(secret) do
    id = {:auth, System.unique_integer([:positive])}

    start_supervised!(
      Supervisor.child_spec(
        {TokenAuthority, secret: secret, clock: &Clock.now/0},
        id: id
      )
    )
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "issued token verifies successfully" do
    auth = start_authority("secret")
    assert {:ok, token, jti} = TokenAuthority.issue(auth, %{user_id: 42}, 300)
    assert is_binary(token)
    assert is_binary(jti)
    assert {:ok, %{user_id: 42}} = TokenAuthority.verify(auth, token)
  end

  test "payload is preserved exactly through round-trip" do
    auth = start_authority("my-secret")
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    assert {:ok, token, _jti} = TokenAuthority.issue(auth, payload, 60)
    assert {:ok, ^payload} = TokenAuthority.verify(auth, token)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    auth = start_authority("key")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "distinct issues get distinct jtis" do
    auth = start_authority("key")
    {:ok, _t1, jti1} = TokenAuthority.issue(auth, "a", 60)
    {:ok, _t2, jti2} = TokenAuthority.issue(auth, "b", 60)
    refute jti1 == jti2
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    auth = start_authority("s3cr3t")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = TokenAuthority.verify(auth, token)
  end

  test "expired token returns :expired" do
    auth = start_authority("s3cr3t")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = TokenAuthority.verify(auth, token)
  end

  test "token expires exactly at ttl boundary" do
    auth = start_authority("s3cr3t")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = TokenAuthority.verify(auth, token)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "token from another authority (different secret) returns :invalid_signature" do
    a = start_authority("secret-a")
    b = start_authority("secret-b")
    {:ok, token, _jti} = TokenAuthority.issue(a, "payload", 300)
    assert {:error, :invalid_signature} = TokenAuthority.verify(b, token)
  end

  test "tampered payload returns :invalid_signature" do
    auth = start_authority("secret")
    {:ok, token, _jti} = TokenAuthority.issue(auth, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = TokenAuthority.verify(auth, tampered)
  end

  # -------------------------------------------------------
  # Revocation
  # -------------------------------------------------------

  test "revoke returns :ok" do
    auth = start_authority("secret")
    {:ok, _token, jti} = TokenAuthority.issue(auth, "data", 300)
    assert :ok = TokenAuthority.revoke(auth, jti)
  end

  test "revoked token returns :revoked" do
    auth = start_authority("secret")
    {:ok, token, jti} = TokenAuthority.issue(auth, "data", 300)
    assert {:ok, "data"} = TokenAuthority.verify(auth, token)
    :ok = TokenAuthority.revoke(auth, jti)
    assert {:error, :revoked} = TokenAuthority.verify(auth, token)
  end

  test "revoking one token does not affect another" do
    auth = start_authority("secret")
    {:ok, t1, jti1} = TokenAuthority.issue(auth, "one", 300)
    {:ok, t2, _jti2} = TokenAuthority.issue(auth, "two", 300)

    :ok = TokenAuthority.revoke(auth, jti1)

    assert {:error, :revoked} = TokenAuthority.verify(auth, t1)
    assert {:ok, "two"} = TokenAuthority.verify(auth, t2)
  end

  test "expiry check takes precedence over revocation check" do
    auth = start_authority("secret")
    {:ok, token, jti} = TokenAuthority.issue(auth, "data", 100)
    :ok = TokenAuthority.revoke(auth, jti)
    Clock.advance(101)
    # Both expired and revoked -> expiry wins.
    assert {:error, :expired} = TokenAuthority.verify(auth, token)
  end

  test "revoking an unissued jti is fine and idempotent" do
    auth = start_authority("secret")
    assert :ok = TokenAuthority.revoke(auth, "never-issued")
    assert :ok = TokenAuthority.revoke(auth, "never-issued")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "data", 300)
    assert {:ok, "data"} = TokenAuthority.verify(auth, token)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    auth = start_authority("secret")
    assert {:error, :malformed} = TokenAuthority.verify(auth, "")
  end

  test "random binary returns :malformed" do
    auth = start_authority("secret")
    assert {:error, :malformed} = TokenAuthority.verify(auth, "notavalidtoken!!!")
  end

  test "non-binary input returns :malformed" do
    auth = start_authority("secret")
    assert {:error, :malformed} = TokenAuthority.verify(auth, 12345)
  end

  test "truncated token returns :malformed" do
    auth = start_authority("secret")
    {:ok, token, _jti} = TokenAuthority.issue(auth, "hello", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = TokenAuthority.verify(auth, truncated)
  end

  test "valid base64 but garbage content returns :malformed" do
    auth = start_authority("secret")
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = TokenAuthority.verify(auth, garbage)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    auth = start_authority("s")
    {:ok, token, _jti} = TokenAuthority.issue(auth, :hello, 60)
    assert {:ok, :hello} = TokenAuthority.verify(auth, token)
  end

  test "supports integer payload" do
    auth = start_authority("s")
    {:ok, token, _jti} = TokenAuthority.issue(auth, 12345, 60)
    assert {:ok, 12345} = TokenAuthority.verify(auth, token)
  end

  test "supports list payload" do
    auth = start_authority("s")
    {:ok, token, _jti} = TokenAuthority.issue(auth, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = TokenAuthority.verify(auth, token)
  end

  test "supports deeply nested map payload" do
    auth = start_authority("s")
    payload = %{a: %{b: %{c: "deep"}}}
    {:ok, token, _jti} = TokenAuthority.issue(auth, payload, 60)
    assert {:ok, ^payload} = TokenAuthority.verify(auth, token)
  end
end
