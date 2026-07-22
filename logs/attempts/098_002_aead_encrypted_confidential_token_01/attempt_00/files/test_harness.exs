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

  @key String.duplicate("k", 32)
  @wrong_key String.duplicate("x", 32)

  defp seal(payload, ttl),
    do: SealedToken.seal(payload, @key, ttl, clock: &Clock.now/0)

  defp open(token),
    do: SealedToken.open(token, @key, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "sealed token opens successfully" do
    token = seal(%{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = open(token)
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = seal(payload, 60)
    assert {:ok, ^payload} = open(token)
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = seal("hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Confidentiality
  # -------------------------------------------------------

  test "payload is encrypted and does not appear in the token bytes" do
    token = seal("SUPERSECRETMARKER", 300)
    {:ok, raw} = Base.url_decode64(token, padding: false)
    assert :binary.match(raw, "SUPERSECRETMARKER") == :nomatch
  end

  test "sealing the same payload twice yields different tokens" do
    t1 = seal(%{a: 1}, 300)
    t2 = seal(%{a: 1}, 300)
    assert t1 != t2
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = seal("data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = open(token)
  end

  test "expired token returns :expired" do
    token = seal("data", 100)
    Clock.advance(101)
    assert {:error, :expired} = open(token)
  end

  test "token expires exactly at ttl boundary" do
    token = seal("data", 50)
    Clock.advance(50)
    assert {:error, :expired} = open(token)
  end

  # -------------------------------------------------------
  # Authentication
  # -------------------------------------------------------

  test "wrong key returns :invalid" do
    token = seal("payload", 300)
    assert {:error, :invalid} = SealedToken.open(token, @wrong_key, clock: &Clock.now/0)
  end

  test "tampered token returns :invalid" do
    token = seal(%{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid} = open(tampered)
  end

  test "authentication is checked before expiry" do
    token = seal("old", 1)
    Clock.advance(200)
    # Even though it is expired, the wrong key cannot decrypt it → :invalid
    assert {:error, :invalid} = SealedToken.open(token, @wrong_key, clock: &Clock.now/0)
  end

  test "right-length but unauthentic bytes return :invalid" do
    garbage = Base.url_encode64(:binary.copy(<<0>>, 40), padding: false)
    assert {:error, :invalid} = open(garbage)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = open("")
  end

  test "non-base64 input returns :malformed" do
    assert {:error, :malformed} = open("notavalidtoken!!!")
  end

  test "too-short decoded input returns :malformed" do
    assert {:error, :malformed} = open("abc")
  end

  test "truncated token returns :malformed" do
    token = seal("hello", 60)
    truncated = binary_part(token, 0, 10)
    assert {:error, :malformed} = open(truncated)
  end

  test "non-binary input returns :malformed" do
    assert {:error, :malformed} = SealedToken.open(12345, @key, clock: &Clock.now/0)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "tokens are not cross-openable across keys" do
    key_a = String.duplicate("a", 32)
    key_b = String.duplicate("b", 32)

    t1 = SealedToken.seal("msg", key_a, 300, clock: &Clock.now/0)
    t2 = SealedToken.seal("msg", key_b, 300, clock: &Clock.now/0)

    assert {:ok, "msg"} = SealedToken.open(t1, key_a, clock: &Clock.now/0)
    assert {:ok, "msg"} = SealedToken.open(t2, key_b, clock: &Clock.now/0)

    assert {:error, :invalid} = SealedToken.open(t1, key_b, clock: &Clock.now/0)
    assert {:error, :invalid} = SealedToken.open(t2, key_a, clock: &Clock.now/0)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = seal(:hello, 60)
    assert {:ok, :hello} = open(token)
  end

  test "supports integer payload" do
    token = seal(12345, 60)
    assert {:ok, 12345} = open(token)
  end

  test "supports list payload" do
    token = seal([1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = open(token)
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = seal(payload, 60)
    assert {:ok, ^payload} = open(token)
  end
end
