defmodule RotatingTokenTest do
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

  defp gen(payload, secret, kid, ttl),
    do: RotatingToken.generate(payload, secret, kid, ttl, clock: &Clock.now/0)

  defp ver(token, keyring),
    do: RotatingToken.verify(token, keyring, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # --- Round-trip -------------------------------------------------------

  test "token signed with a key verifies against a keyring holding it" do
    token = gen(%{user_id: 42}, "secret-1", "k1", 300)
    assert {:ok, %{user_id: 42}} = ver(token, %{"k1" => "secret-1"})
  end

  test "payload preserved exactly" do
    payload = %{role: "admin", meta: [1, 2, 3]}
    token = gen(payload, "s", "k1", 60)
    assert {:ok, ^payload} = ver(token, %{"k1" => "s"})
  end

  test "token is URL-safe" do
    token = gen("hi", "s", "k1", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # --- Rotation ---------------------------------------------------------

  test "verifies against a multi-key ring" do
    keyring = %{"k1" => "secret-1", "k2" => "secret-2"}
    t1 = gen("a", "secret-1", "k1", 300)
    t2 = gen("b", "secret-2", "k2", 300)
    assert {:ok, "a"} = ver(t1, keyring)
    assert {:ok, "b"} = ver(t2, keyring)
  end

  test "old token still verifies while its key is retained" do
    old = gen("legacy", "secret-1", "k1", 300)
    ring_after_rotation = %{"k1" => "secret-1", "k2" => "secret-2"}
    assert {:ok, "legacy"} = ver(old, ring_after_rotation)
  end

  test "token with unknown kid returns :unknown_key" do
    token = gen("x", "secret-2", "k2", 300)
    assert {:error, :unknown_key} = ver(token, %{"k1" => "secret-1"})
  end

  test "removing a key retires its tokens with :unknown_key" do
    old = gen("legacy", "secret-1", "k1", 300)
    new_ring = %{"k2" => "secret-2"}
    assert {:error, :unknown_key} = ver(old, new_ring)
  end

  # --- Signature --------------------------------------------------------

  test "known kid but wrong secret returns :invalid_signature" do
    token = gen("payload", "right", "k1", 300)
    assert {:error, :invalid_signature} = ver(token, %{"k1" => "wrong"})
  end

  test "tampered token returns :invalid_signature" do
    token = gen(%{role: "user"}, "secret-1", "k1", 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert ver(tampered, %{"k1" => "secret-1"}) in [
             {:error, :invalid_signature},
             {:error, :malformed},
             {:error, :unknown_key}
           ]
  end

  test "unknown key precedence over expiry" do
    token = gen("old", "secret-2", "k2", 1)
    Clock.advance(200)
    assert {:error, :unknown_key} = ver(token, %{"k1" => "secret-1"})
  end

  test "signature precedence over expiry" do
    token = gen("old", "right", "k1", 1)
    Clock.advance(200)
    assert {:error, :invalid_signature} = ver(token, %{"k1" => "wrong"})
  end

  # --- Expiry -----------------------------------------------------------

  test "valid just before expiry" do
    token = gen("data", "s", "k1", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, %{"k1" => "s"})
  end

  test "expired token returns :expired" do
    token = gen("data", "s", "k1", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, %{"k1" => "s"})
  end

  test "expires exactly at ttl boundary" do
    token = gen("data", "s", "k1", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, %{"k1" => "s"})
  end

  # --- Malformed --------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", %{"k1" => "s"})
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", %{"k1" => "s"})
  end

  test "truncated token returns :malformed" do
    token = gen("hello", "s", "k1", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, %{"k1" => "s"})
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("nope not a token", padding: false)
    assert {:error, :malformed} = ver(garbage, %{"k1" => "s"})
  end

  # --- Payload types ----------------------------------------------------

  test "supports atom, integer, list, nested map payloads" do
    ring = %{"k1" => "s"}
    assert {:ok, :hi} = ver(gen(:hi, "s", "k1", 60), ring)
    assert {:ok, 123} = ver(gen(123, "s", "k1", 60), ring)
    assert {:ok, [1, "b", :c]} = ver(gen([1, "b", :c], "s", "k1", 60), ring)
    nested = %{a: %{b: %{c: "deep"}}}
    assert {:ok, ^nested} = ver(gen(nested, "s", "k1", 60), ring)
  end
end