defmodule ScopedTokenTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic time testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &(&1 + seconds))
    def set(seconds), do: Agent.update(__MODULE__, fn _ -> seconds end)
  end

  defp gen(payload, secret, aud, ttl, gen_opts \\ []) do
    ScopedToken.generate(payload, secret, aud, ttl, Keyword.put(gen_opts, :clock, &Clock.now/0))
  end

  defp ver(token, secret, aud) do
    ScopedToken.verify(token, secret, aud, clock: &Clock.now/0)
  end

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "generated token verifies for the matching audience" do
    token = gen(%{user_id: 42}, "secret", "web", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = ver(token, "secret", "web")
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = gen(payload, "my-secret", "web", 60)
    assert {:ok, ^payload} = ver(token, "my-secret", "web")
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = gen("hello", "key", "web", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = gen("data", "s3cr3t", "web", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, "s3cr3t", "web")
  end

  test "expired token returns :expired" do
    token = gen("data", "s3cr3t", "web", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, "s3cr3t", "web")
  end

  test "token expires exactly at ttl boundary" do
    token = gen("data", "s3cr3t", "web", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, "s3cr3t", "web")
  end

  # -------------------------------------------------------
  # Not-before window
  # -------------------------------------------------------

  test "token is not yet valid before its not-before time" do
    token = gen("data", "s", "web", 300, not_before: 100)
    # At issue time (0 elapsed) the not-before is 100 seconds away.
    assert {:error, :not_yet_valid} = ver(token, "s", "web")
  end

  test "token is still not valid one second before not-before time" do
    token = gen("data", "s", "web", 300, not_before: 100)
    Clock.advance(99)
    assert {:error, :not_yet_valid} = ver(token, "s", "web")
  end

  test "token becomes valid exactly at its not-before time" do
    token = gen("data", "s", "web", 300, not_before: 100)
    Clock.advance(100)
    assert {:ok, "data"} = ver(token, "s", "web")
  end

  test "default not_before makes the token immediately valid" do
    token = gen("data", "s", "web", 300)
    assert {:ok, "data"} = ver(token, "s", "web")
  end

  # -------------------------------------------------------
  # Audience binding
  # -------------------------------------------------------

  test "wrong audience returns :audience_mismatch" do
    token = gen("x", "s", "mobile", 300)
    assert {:error, :audience_mismatch} = ver(token, "s", "web")
  end

  test "audience check takes precedence over expiry check" do
    token = gen("x", "s", "web", 1)
    Clock.advance(100)
    # Expired, but presented for the wrong audience -> audience wins.
    assert {:error, :audience_mismatch} = ver(token, "s", "mobile")
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "wrong secret returns :invalid_signature" do
    token = gen("payload", "correct-secret", "web", 300)
    assert {:error, :invalid_signature} = ver(token, "wrong-secret", "web")
  end

  test "signature check takes precedence over audience check" do
    token = gen("x", "correct", "web", 300)
    # Wrong secret AND wrong audience -> signature wins.
    assert {:error, :invalid_signature} = ver(token, "wrong", "mobile")
  end

  test "tampered token returns :invalid_signature" do
    token = gen(%{role: "user"}, "secret", "web", 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = ver(tampered, "secret", "web")
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", "secret", "web")
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", "secret", "web")
  end

  test "truncated token returns :malformed" do
    token = gen("hello", "secret", "web", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, "secret", "web")
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = ver(garbage, "secret", "web")
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = gen(:hello, "s", "web", 60)
    assert {:ok, :hello} = ver(token, "s", "web")
  end

  test "supports integer payload" do
    token = gen(12345, "s", "web", 60)
    assert {:ok, 12345} = ver(token, "s", "web")
  end

  test "supports list payload" do
    token = gen([1, "two", :three], "s", "web", 60)
    assert {:ok, [1, "two", :three]} = ver(token, "s", "web")
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = gen(payload, "s", "web", 60)
    assert {:ok, ^payload} = ver(token, "s", "web")
  end
end
