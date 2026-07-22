defmodule RotatingTokenTest do
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

  defp gen(payload, keyring, active, ttl),
    do: RotatingToken.generate(payload, keyring, active, ttl, clock: &Clock.now/0)

  defp ver(token, keyring),
    do: RotatingToken.verify(token, keyring, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "generated token verifies successfully with the active key" do
    keyring = %{"k1" => "secret-one"}
    token = gen(%{user_id: 42}, keyring, "k1", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = ver(token, keyring)
  end

  test "payload is preserved exactly through round-trip" do
    keyring = %{"k1" => "my-secret"}
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = gen(payload, keyring, "k1", 60)
    assert {:ok, ^payload} = ver(token, keyring)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    keyring = %{"k1" => "key"}
    token = gen("hello", keyring, "k1", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    keyring = %{"k1" => "s3cr3t"}
    token = gen("data", keyring, "k1", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, keyring)
  end

  test "expired token returns :expired" do
    keyring = %{"k1" => "s3cr3t"}
    token = gen("data", keyring, "k1", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, keyring)
  end

  test "token expires exactly at ttl boundary" do
    keyring = %{"k1" => "s3cr3t"}
    token = gen("data", keyring, "k1", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, keyring)
  end

  # -------------------------------------------------------
  # Signature validation (same key id, different secret)
  # -------------------------------------------------------

  test "known key id with wrong secret returns :invalid_signature" do
    signing = %{"k1" => "correct-secret"}
    checking = %{"k1" => "wrong-secret"}
    token = gen("payload", signing, "k1", 300)
    assert {:error, :invalid_signature} = ver(token, checking)
  end

  test "tampered token returns :invalid_signature" do
    keyring = %{"k1" => "secret"}
    token = gen(%{role: "user"}, keyring, "k1", 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = ver(tampered, keyring)
  end

  test "signature check takes precedence over expiry check" do
    token = gen("old", %{"k1" => "correct"}, "k1", 1)
    Clock.advance(200)
    # Known key id, wrong secret, and also expired -> signature wins.
    assert {:error, :invalid_signature} = ver(token, %{"k1" => "wrong"})
  end

  # -------------------------------------------------------
  # Unknown key
  # -------------------------------------------------------

  test "key id absent from keyring returns :unknown_key" do
    token = gen("x", %{"k1" => "s1"}, "k1", 300)
    assert {:error, :unknown_key} = ver(token, %{"k2" => "s2"})
  end

  test "unknown key takes precedence over expiry" do
    token = gen("x", %{"k1" => "s1"}, "k1", 1)
    Clock.advance(100)
    assert {:error, :unknown_key} = ver(token, %{"k2" => "s2"})
  end

  # -------------------------------------------------------
  # Key rotation
  # -------------------------------------------------------

  test "tokens signed with different key ids both verify against the shared keyring" do
    keyring = %{"2023" => "old-secret", "2024" => "new-secret"}

    old = gen("issued-under-old", keyring, "2023", 300)
    new = gen("issued-under-new", keyring, "2024", 300)

    assert {:ok, "issued-under-old"} = ver(old, keyring)
    assert {:ok, "issued-under-new"} = ver(new, keyring)
  end

  test "an old-key token still verifies after the active key rotates" do
    # Old token signed only with the retiring key.
    old = gen("legacy", %{"2023" => "old-secret"}, "2023", 300)

    # New keyring adds the current key but keeps the old one for verification.
    rotated = %{"2023" => "old-secret", "2024" => "new-secret"}
    assert {:ok, "legacy"} = ver(old, rotated)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", %{"k1" => "s"})
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", %{"k1" => "s"})
  end

  test "truncated token returns :malformed" do
    token = gen("hello", %{"k1" => "s"}, "k1", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, %{"k1" => "s"})
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = ver(garbage, %{"k1" => "s"})
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    keyring = %{"k1" => "s"}
    token = gen(:hello, keyring, "k1", 60)
    assert {:ok, :hello} = ver(token, keyring)
  end

  test "supports integer payload" do
    keyring = %{"k1" => "s"}
    token = gen(12345, keyring, "k1", 60)
    assert {:ok, 12345} = ver(token, keyring)
  end

  test "supports list payload" do
    keyring = %{"k1" => "s"}
    token = gen([1, "two", :three], keyring, "k1", 60)
    assert {:ok, [1, "two", :three]} = ver(token, keyring)
  end

  test "supports deeply nested map payload" do
    keyring = %{"k1" => "s"}
    payload = %{a: %{b: %{c: "deep"}}}
    token = gen(payload, keyring, "k1", 60)
    assert {:ok, ^payload} = ver(token, keyring)
  end
end
