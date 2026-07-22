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

  @keyring %{"k1" => "secret-one", "k2" => "secret-two"}

  defp generate(payload, ttl, kid \\ "k1"),
    do: RotatingToken.generate(payload, @keyring, kid, ttl, clock: &Clock.now/0)

  defp verify(token, keyring \\ @keyring),
    do: RotatingToken.verify(token, keyring, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "generated token verifies successfully" do
    token = generate(%{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = verify(token)
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = generate(payload, 60)
    assert {:ok, ^payload} = verify(token)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = generate("hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Key selection and rotation
  # -------------------------------------------------------

  test "token signed with the second key also verifies" do
    token = RotatingToken.generate(%{u: 1}, @keyring, "k2", 300, clock: &Clock.now/0)
    assert {:ok, %{u: 1}} = verify(token)
  end

  test "old-key token still verifies while its key remains in the keyring" do
    token = generate("legacy", 300, "k1")
    # k1 retained alongside a newer key
    keyring = %{"k1" => "secret-one", "k3" => "secret-three"}
    assert {:ok, "legacy"} = RotatingToken.verify(token, keyring, clock: &Clock.now/0)
  end

  test "token whose key id is not in the keyring returns :unknown_key" do
    token = generate("x", 300, "k1")
    assert {:error, :unknown_key} = verify(token, %{"k2" => "secret-two"})
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "wrong secret for a known key id returns :invalid_signature" do
    token = generate("x", 300, "k1")
    assert {:error, :invalid_signature} = verify(token, %{"k1" => "not-the-real-secret"})
  end

  test "tampered payload returns :invalid_signature" do
    token = generate(%{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = verify(tampered)
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = generate("data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = verify(token)
  end

  test "expired token returns :expired" do
    token = generate("data", 100)
    Clock.advance(101)
    assert {:error, :expired} = verify(token)
  end

  test "token expires exactly at ttl boundary" do
    token = generate("data", 50)
    Clock.advance(50)
    assert {:error, :expired} = verify(token)
  end

  # -------------------------------------------------------
  # Precedence
  # -------------------------------------------------------

  test "signature check takes precedence over expiry check" do
    token = generate("old", 1, "k1")
    Clock.advance(200)
    assert {:error, :invalid_signature} = verify(token, %{"k1" => "wrong-secret"})
  end

  test "unknown-key check takes precedence over expiry check" do
    token = generate("old", 1, "k1")
    Clock.advance(200)
    assert {:error, :unknown_key} = verify(token, %{"k2" => "secret-two"})
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = verify("")
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = verify("notavalidtoken!!!")
  end

  test "truncated token returns :malformed" do
    token = generate("hello", 60)
    truncated = binary_part(token, 0, 10)
    assert {:error, :malformed} = verify(truncated)
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = verify(garbage)
  end

  test "non-binary input returns :malformed" do
    assert {:error, :malformed} = RotatingToken.verify(12345, @keyring, clock: &Clock.now/0)
  end

  # -------------------------------------------------------
  # Key independence across ids
  # -------------------------------------------------------

  test "a token cannot be verified against a different key id's secret" do
    t1 = generate("msg", 300, "k1")
    t2 = generate("msg", 300, "k2")

    assert {:ok, "msg"} = verify(t1)
    assert {:ok, "msg"} = verify(t2)

    # k1's token verified against a keyring where k1 maps to k2's secret
    assert {:error, :invalid_signature} = verify(t1, %{"k1" => "secret-two"})
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = generate(:hello, 60)
    assert {:ok, :hello} = verify(token)
  end

  test "supports integer payload" do
    token = generate(12345, 60)
    assert {:ok, 12345} = verify(token)
  end

  test "supports list payload" do
    token = generate([1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = verify(token)
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = generate(payload, 60)
    assert {:ok, ^payload} = verify(token)
  end
end
