defmodule SealedTokenTest do
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

  # 32-byte keys (AES-256).
  @key String.duplicate("k", 32)
  @key_a String.duplicate("a", 32)
  @key_b String.duplicate("b", 32)

  defp seal(payload, key, ttl),
    do: SealedToken.seal(payload, key, ttl, clock: &Clock.now/0)

  defp open(token, key),
    do: SealedToken.open(token, key, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "sealed token opens successfully" do
    token = seal(%{user_id: 42}, @key, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = open(token, @key)
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = seal("hello", @key, 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "sealing the same payload twice yields different tokens (random nonce)" do
    t1 = seal("same", @key, 60)
    t2 = seal("same", @key, 60)
    refute t1 == t2
    assert {:ok, "same"} = open(t1, @key)
    assert {:ok, "same"} = open(t2, @key)
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = seal("data", @key, 100)
    Clock.advance(99)
    assert {:ok, "data"} = open(token, @key)
  end

  test "expired token returns :expired" do
    token = seal("data", @key, 100)
    Clock.advance(101)
    assert {:error, :expired} = open(token, @key)
  end

  test "token expires exactly at ttl boundary" do
    token = seal("data", @key, 50)
    Clock.advance(50)
    assert {:error, :expired} = open(token, @key)
  end

  # -------------------------------------------------------
  # Authentication
  # -------------------------------------------------------

  test "wrong key returns :invalid" do
    token = seal("payload", @key_a, 300)
    assert {:error, :invalid} = open(token, @key_b)
  end

  test "tampered token returns :invalid" do
    token = seal(%{role: "user"}, @key, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid} = open(tampered, @key)
  end

  test "authentication check takes precedence over expiry check" do
    token = seal("old", @key_a, 1)
    Clock.advance(200)
    # Expired, but the wrong key means authentication fails first.
    assert {:error, :invalid} = open(token, @key_b)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = open("", @key)
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = open("notavalidtoken!!!", @key)
  end

  test "truncated token returns :malformed" do
    token = seal("hello", @key, 60)
    truncated = binary_part(token, 0, div(byte_size(token), 4))
    assert {:error, :malformed} = open(truncated, @key)
  end

  test "valid base64 but too-short content returns :malformed" do
    garbage = Base.url_encode64("too short", padding: false)
    assert {:error, :malformed} = open(garbage, @key)
  end

  test "non-binary token returns :malformed" do
    assert {:error, :malformed} = open(12345, @key)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "tokens are not cross-openable across keys" do
    t1 = seal("msg", @key_a, 300)
    t2 = seal("msg", @key_b, 300)

    assert {:ok, "msg"} = open(t1, @key_a)
    assert {:ok, "msg"} = open(t2, @key_b)

    assert {:error, :invalid} = open(t1, @key_b)
    assert {:error, :invalid} = open(t2, @key_a)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = seal(:hello, @key, 60)
    assert {:ok, :hello} = open(token, @key)
  end

  test "supports integer payload" do
    token = seal(12345, @key, 60)
    assert {:ok, 12345} = open(token, @key)
  end

  test "supports list payload" do
    token = seal([1, "two", :three], @key, 60)
    assert {:ok, [1, "two", :three]} = open(token, @key)
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end
end
