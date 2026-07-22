defmodule RevocableTokenTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &(&1 + seconds))
    def set(seconds), do: Agent.update(__MODULE__, fn _ -> seconds end)
  end

  defp gen(payload, secret, ttl),
    do: RevocableToken.generate(payload, secret, ttl, clock: &Clock.now/0)

  defp ver(token, secret),
    do: RevocableToken.verify(RevocableToken, token, secret, clock: &Clock.now/0)

  defp revoke(token),
    do: RevocableToken.revoke(RevocableToken, token)

  setup do
    start_supervised!({Clock, 1_000_000})
    start_supervised!({RevocableToken, name: RevocableToken})
    :ok
  end

  # --- Round-trip -------------------------------------------------------

  test "generated token verifies successfully" do
    token = gen(%{user_id: 42}, "secret", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = ver(token, "secret")
  end

  test "payload preserved exactly" do
    payload = %{role: "admin", meta: [1, 2, 3]}
    token = gen(payload, "s", 60)
    assert {:ok, ^payload} = ver(token, "s")
  end

  test "token is URL-safe" do
    token = gen("hello", "key", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "two generated tokens differ (unique jti)" do
    assert gen("x", "s", 60) != gen("x", "s", 60)
  end

  # --- Expiry -----------------------------------------------------------

  test "valid just before expiry" do
    token = gen("data", "s3cr3t", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, "s3cr3t")
  end

  test "expired token returns :expired" do
    token = gen("data", "s3cr3t", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, "s3cr3t")
  end

  test "expires exactly at ttl boundary" do
    token = gen("data", "s3cr3t", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, "s3cr3t")
  end

  # --- Signature --------------------------------------------------------

  test "wrong secret returns :invalid_signature" do
    token = gen("payload", "correct", 300)
    assert {:error, :invalid_signature} = ver(token, "wrong")
  end

  test "tampered token returns :invalid_signature" do
    token = gen(%{role: "user"}, "secret", 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = ver(tampered, "secret")
  end

  test "signature precedence over expiry" do
    token = gen("old", "secret", 1)
    Clock.advance(200)
    assert {:error, :invalid_signature} = ver(token, "bad")
  end

  # --- Revocation -------------------------------------------------------

  test "revoked token returns :revoked" do
    token = gen(%{id: 7}, "secret", 300)
    assert {:ok, %{id: 7}} = ver(token, "secret")
    assert :ok = revoke(token)
    assert {:error, :revoked} = ver(token, "secret")
  end

  test "revocation is per-token (jti scoped)" do
    t1 = gen("one", "secret", 300)
    t2 = gen("two", "secret", 300)
    assert :ok = revoke(t1)
    assert {:error, :revoked} = ver(t1, "secret")
    assert {:ok, "two"} = ver(t2, "secret")
  end

  test "expiry precedence over revocation" do
    token = gen("data", "secret", 10)
    assert :ok = revoke(token)
    Clock.advance(20)
    assert {:error, :expired} = ver(token, "secret")
  end

  test "signature precedence over revocation" do
    token = gen("data", "secret", 300)
    assert :ok = revoke(token)
    assert {:error, :invalid_signature} = ver(token, "wrong")
  end

  test "revoke of unparsable token returns :malformed" do
    assert {:error, :malformed} = revoke("not-a-real-token!!!")
  end

  test "revoke does not require the secret" do
    token = gen("data", "the-secret", 300)
    assert :ok = revoke(token)
    assert {:error, :revoked} = ver(token, "the-secret")
  end

  # --- Malformed --------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", "secret")
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", "secret")
  end

  test "truncated token returns :malformed" do
    token = gen("hello", "secret", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, "secret")
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("nope not a token", padding: false)
    assert {:error, :malformed} = ver(garbage, "secret")
  end

  # --- Payload types ----------------------------------------------------

  test "supports atom, integer, list, nested map payloads" do
    assert {:ok, :hi} = ver(gen(:hi, "s", 60), "s")
    assert {:ok, 123} = ver(gen(123, "s", 60), "s")
    assert {:ok, [1, "b", :c]} = ver(gen([1, "b", :c], "s", 60), "s")
    nested = %{a: %{b: %{c: "deep"}}}
    assert {:ok, ^nested} = ver(gen(nested, "s", 60), "s")
  end
end