defmodule ScopedTokenTest do
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

  defp gen(payload, secret, ttl, opts \\ []) do
    ScopedToken.generate(payload, secret, ttl, Keyword.put(opts, :clock, &Clock.now/0))
  end

  defp ver(token, secret, opts \\ []) do
    ScopedToken.verify(token, secret, Keyword.put(opts, :clock, &Clock.now/0))
  end

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # --- Round-trip -------------------------------------------------------

  test "plain token verifies successfully" do
    token = gen(%{user_id: 42}, "secret", 300)
    assert {:ok, %{user_id: 42}} = ver(token, "secret")
  end

  test "payload preserved exactly" do
    payload = %{role: "admin", meta: [1, 2, 3]}
    token = gen(payload, "s", 60)
    assert {:ok, ^payload} = ver(token, "s")
  end

  test "token is URL-safe" do
    token = gen("hi", "s", 60, audience: "api", scopes: ["read"])
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # --- Expiry -----------------------------------------------------------

  test "valid just before expiry" do
    token = gen("data", "s", 100)
    Clock.advance(99)
    assert {:ok, "data"} = ver(token, "s")
  end

  test "expired token returns :expired" do
    token = gen("data", "s", 100)
    Clock.advance(101)
    assert {:error, :expired} = ver(token, "s")
  end

  test "expires exactly at ttl boundary" do
    token = gen("data", "s", 50)
    Clock.advance(50)
    assert {:error, :expired} = ver(token, "s")
  end

  # --- Not-before -------------------------------------------------------

  test "token not yet valid before not_before" do
    token = gen("data", "s", 300, not_before: 100)
    assert {:error, :not_yet_valid} = ver(token, "s")
  end

  test "token becomes valid exactly at not_before" do
    token = gen("data", "s", 300, not_before: 100)
    Clock.advance(100)
    assert {:ok, "data"} = ver(token, "s")
  end

  test "not_before precedence over expiry-independent path" do
    token = gen("data", "s", 300, not_before: 50)
    Clock.advance(10)
    assert {:error, :not_yet_valid} = ver(token, "s")
  end

  # --- Signature --------------------------------------------------------

  test "wrong secret returns :invalid_signature" do
    token = gen("payload", "correct", 300)
    assert {:error, :invalid_signature} = ver(token, "wrong")
  end

  test "signature precedence over not_yet_valid" do
    token = gen("data", "correct", 300, not_before: 100)
    assert {:error, :invalid_signature} = ver(token, "wrong")
  end

  test "signature precedence over audience" do
    token = gen("data", "correct", 300, audience: "api")
    assert {:error, :invalid_signature} = ver(token, "wrong", audience: "other")
  end

  test "tampered token returns :invalid_signature" do
    token = gen(%{role: "user"}, "secret", 300)

    # Flip the first base64 character: it decodes into the leading bytes of the
    # `issued_at` timestamp, a signed-64 field that parses for any bit pattern.
    # This guarantees the structure still parses (no length-prefix corruption)
    # so the check reaches HMAC verification and fails there.
    tampered =
      token
      |> String.graphemes()
      |> List.update_at(0, fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = ver(tampered, "secret")
  end

  # --- Audience ---------------------------------------------------------

  test "matching audience passes" do
    token = gen("data", "s", 300, audience: "api")
    assert {:ok, "data"} = ver(token, "s", audience: "api")
  end

  test "mismatched audience returns :audience_mismatch" do
    token = gen("data", "s", 300, audience: "api")
    assert {:error, :audience_mismatch} = ver(token, "s", audience: "other")
  end

  test "expected audience but token has none returns :audience_mismatch" do
    token = gen("data", "s", 300)
    assert {:error, :audience_mismatch} = ver(token, "s", audience: "api")
  end

  test "no expected audience skips the check" do
    token = gen("data", "s", 300, audience: "api")
    assert {:ok, "data"} = ver(token, "s")
  end

  test "audience checked after expiry" do
    token = gen("data", "s", 10, audience: "api")
    Clock.advance(20)
    assert {:error, :expired} = ver(token, "s", audience: "other")
  end

  # --- Scopes -----------------------------------------------------------

  test "sufficient scopes pass" do
    token = gen("data", "s", 300, scopes: ["read", "write"])
    assert {:ok, "data"} = ver(token, "s", scopes: ["read"])
  end

  test "all required scopes must be present" do
    token = gen("data", "s", 300, scopes: ["read", "write"])
    assert {:ok, "data"} = ver(token, "s", scopes: ["read", "write"])
  end

  test "missing required scope returns :insufficient_scope" do
    token = gen("data", "s", 300, scopes: ["read"])
    assert {:error, :insufficient_scope} = ver(token, "s", scopes: ["admin"])
  end

  test "no required scopes passes regardless" do
    token = gen("data", "s", 300, scopes: [])
    assert {:ok, "data"} = ver(token, "s")
  end

  test "audience checked before scope" do
    token = gen("data", "s", 300, audience: "api", scopes: ["read"])
    assert {:error, :audience_mismatch} = ver(token, "s", audience: "other", scopes: ["admin"])
  end

  # --- Malformed --------------------------------------------------------

  test "empty string returns :malformed" do
    assert {:error, :malformed} = ver("", "s")
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = ver("notavalidtoken!!!", "s")
  end

  test "truncated token returns :malformed" do
    token = gen("hello", "s", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = ver(truncated, "s")
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("nope not a token", padding: false)
    assert {:error, :malformed} = ver(garbage, "s")
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