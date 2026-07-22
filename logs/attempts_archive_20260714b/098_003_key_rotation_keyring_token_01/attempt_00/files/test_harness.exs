defmodule KeyringTokenTest do
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

  # The keyring maps key ids to their signing secrets.
  @full %{"k1" => "secret-one", "k2" => "secret-two"}

  defp gen(payload, key_id, ttl, keyring \\ @full),
    do: KeyringToken.generate(payload, keyring, key_id, ttl, clock: &Clock.now/0)

  defp ver(token, keyring),
    do: KeyringToken.verify(token, keyring, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "generated token verifies successfully against the full keyring" do
    token = gen(%{user_id: 42}, "k1", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = ver(token, @full)
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = gen(payload, "k2", 60)
    assert {:ok, ^payload} = ver(token, @full)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = gen("hello", "k1", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = gen("data", "k1", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, @full)
  end

  test "expired token returns :expired" do
    token = gen("data", "k1", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, @full)
  end

  test "token expires exactly at ttl boundary" do
    token = gen("data", "k1", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, @full)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "known key with wrong secret returns :invalid_signature" do
    token = gen("payload", "k1", 300)
    # Same key id "k1", but the keyring maps it to a different secret.
    wrong = %{"k1" => "not-secret-one"}
    assert {:error, :invalid_signature} = ver(token, wrong)
  end

  test "tampered token returns :invalid_signature" do
    token = gen(%{role: "user"}, "k1", 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = ver(tampered, @full)
  end

  test "signature check takes precedence over expiry check" do
    token = gen("old", "k1", 1)
    Clock.advance(200)
    # Expired, but the keyring maps "k1" to the wrong secret -> invalid_signature.
    assert {:error, :invalid_signature} = ver(token, %{"k1" => "bad"})
  end

  # -------------------------------------------------------
  # Unknown key / rotation
  # -------------------------------------------------------

  test "unknown embedded key id returns :unknown_key" do
    token = gen("msg", "k1", 300)
    # A keyring that does not contain "k1".
    assert {:error, :unknown_key} = ver(token, %{"k2" => "secret-two"})
  end

  test "rotation: token still verifies while its key remains in the keyring, then becomes unknown once dropped" do
    token = gen("msg", "k1", 300)

    # During the rotation window both keys are present.
    assert {:ok, "msg"} = ver(token, @full)

    # After the old key is retired (dropped from the keyring) it is unknown.
    assert {:error, :unknown_key} = ver(token, %{"k2" => "secret-two"})
  end

  test "unknown key takes precedence over expiry" do
    token = gen("old", "k1", 1)
    Clock.advance(200)
    # Expired, but the key is absent -> :unknown_key wins.
    assert {:error, :unknown_key} = ver(token, %{"k2" => "secret-two"})
  end

  # -------------------------------------------------------
  # generate/5 requires a known key id
  # -------------------------------------------------------

  test "generate raises ArgumentError when key_id is not in the keyring" do
    assert_raise ArgumentError, fn ->
      gen("msg", "nope", 300)
    end
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", @full)
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", @full)
  end

  test "truncated token returns :malformed" do
    token = gen("hello", "k1", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, @full)
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = ver(garbage, @full)
  end

  test "non-binary token input returns :malformed" do
    assert {:error, :malformed} = ver(12345, @full)
  end

  test "keyring that is not a map returns :malformed" do
    token = gen("hi", "k1", 60)
    assert {:error, :malformed} = KeyringToken.verify(token, "not-a-map", clock: &Clock.now/0)
  end

  # -------------------------------------------------------
  # Different keys produce independent tokens
  # -------------------------------------------------------

  test "the embedded key id selects which secret verifies the token" do
    t1 = gen("msg", "k1", 300)
    t2 = gen("msg", "k2", 300)

    assert {:ok, "msg"} = ver(t1, @full)
    assert {:ok, "msg"} = ver(t2, @full)

    # k1's token is unknown to a keyring holding only k2, and vice versa.
    assert {:error, :unknown_key} = ver(t1, %{"k2" => "secret-two"})
    assert {:error, :unknown_key} = ver(t2, %{"k1" => "secret-one"})
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = gen(:hello, "k1", 60)
    assert {:ok, :hello} = ver(token, @full)
  end

  test "supports integer payload" do
    token = gen(12345, "k1", 60)
    assert {:ok, 12345} = ver(token, @full)
  end

  test "supports list payload" do
    token = gen([1, "two", :three], "k1", 60)
    assert {:ok, [1, "two", :three]} = ver(token, @full)
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = gen(payload, "k2", 60)
    assert {:ok, ^payload} = ver(token, @full)
  end
end
