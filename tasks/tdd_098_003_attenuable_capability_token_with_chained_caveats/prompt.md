# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule CapabilityTokenTest do
  use ExUnit.Case, async: false

  @root "root-key-abc"

  # --- Wire-format helpers (the format is fully specified in the prompt) ---

  defp raw(token) do
    {:ok, bin} = Base.url_decode64(token, padding: false)
    <<1, id_size::16, id::binary-size(id_size), count::16, rest::binary>> = bin
    {caveats, <<sig::binary-size(32)>>} = take(count, rest, [])
    {id, caveats, sig}
  end

  defp take(0, rest, acc), do: {Enum.reverse(acc), rest}

  defp take(n, <<len::16, c::binary-size(len), rest::binary>>, acc),
    do: take(n - 1, rest, [c | acc])

  defp pack(id, caveats, sig) do
    body =
      for c <- caveats, into: <<>> do
        <<byte_size(c)::16, c::binary>>
      end

    Base.url_encode64(
      <<1, byte_size(id)::16, id::binary, length(caveats)::16, body::binary, sig::binary>>,
      padding: false
    )
  end

  defp attenuate!(token, caveat) do
    {:ok, t} = CapabilityToken.attenuate(token, caveat)
    t
  end

  # -------------------------------------------------------
  # Minting and round-trip
  # -------------------------------------------------------

  test "a freshly minted token authorizes with any context" do
    token = CapabilityToken.mint(@root, "user:42")
    assert is_binary(token)
    assert :ok = CapabilityToken.authorize(token, @root, %{})
    assert :ok = CapabilityToken.authorize(token, @root, %{now: 1_000, action: "read"})
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token =
      @root
      |> CapabilityToken.mint("user:42")
      |> attenuate!("action = read")

    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  test "inspect_token exposes identifier and empty caveat list" do
    token = CapabilityToken.mint(@root, "svc:billing")
    assert {:ok, %{identifier: "svc:billing", caveats: []}} = CapabilityToken.inspect_token(token)
  end

  test "inspect_token lists caveats in attachment order" do
    token =
      @root
      |> CapabilityToken.mint("user:1")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")
      |> attenuate!("expires_at = 500")

    assert {:ok, %{identifier: "user:1", caveats: caveats}} =
             CapabilityToken.inspect_token(token)

    assert caveats == ["action = read", "resource_prefix = /docs/", "expires_at = 500"]
  end

  test "attenuate does not mutate the original token" do
    base = CapabilityToken.mint(@root, "user:1")
    narrowed = attenuate!(base, "action = read")

    refute base == narrowed
    assert {:ok, %{caveats: []}} = CapabilityToken.inspect_token(base)
    assert {:ok, %{caveats: ["action = read"]}} = CapabilityToken.inspect_token(narrowed)
    assert :ok = CapabilityToken.authorize(base, @root, %{action: "write"})
  end

  test "attenuation works without the root key and the result still verifies" do
    base = CapabilityToken.mint(@root, "user:1")
    # No key involved in this step at all.
    narrowed = attenuate!(base, "action = read")
    assert :ok = CapabilityToken.authorize(narrowed, @root, %{action: "read"})
  end

  # -------------------------------------------------------
  # Caveat semantics
  # -------------------------------------------------------

  test "expires_at is satisfied strictly before the expiry second" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100")

    assert :ok = CapabilityToken.authorize(token, @root, %{now: 99})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: 100})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: 101})
  end

  test "expires_at fails closed when the context has no :now" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100")

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{action: "read"})
  end

  test "expires_at with a non-integer value fails closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = soon")

    assert {:error, {:caveat_failed, "expires_at = soon"}} =
             CapabilityToken.authorize(token, @root, %{now: 1})
  end

  test "action caveat requires an exact match" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")

    assert :ok = CapabilityToken.authorize(token, @root, %{action: "read"})

    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write"})

    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{})
  end

  test "resource_prefix caveat matches by prefix" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "resource_prefix = /docs/")

    assert :ok = CapabilityToken.authorize(token, @root, %{resource: "/docs/a/b.txt"})
    assert :ok = CapabilityToken.authorize(token, @root, %{resource: "/docs/"})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{resource: "/secrets/x"})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{})
  end

  test "unknown caveat keys fail closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "ip_range = 10.0.0.0/8")

    assert {:error, {:caveat_failed, "ip_range = 10.0.0.0/8"}} =
             CapabilityToken.authorize(token, @root, %{now: 1, action: "read"})
  end

  test "a caveat without the separator fails closed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "always-allow")

    assert {:error, {:caveat_failed, "always-allow"}} =
             CapabilityToken.authorize(token, @root, %{now: 1})
  end

  test "all caveats must hold simultaneously" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")
      |> attenuate!("expires_at = 500")

    ctx = %{action: "read", resource: "/docs/x", now: 499}
    assert :ok = CapabilityToken.authorize(token, @root, ctx)

    assert {:error, {:caveat_failed, "expires_at = 500"}} =
             CapabilityToken.authorize(token, @root, %{ctx | now: 500})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{ctx | resource: "/etc/passwd"})
  end

  test "the first unsatisfied caveat in attachment order is reported" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("expires_at = 100")

    # Both caveats fail; the earlier one wins.
    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write", now: 999})
  end

  test "attenuation only narrows: adding a caveat can never re-open a denial" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("action = write")

    # Contradictory caveats: nothing satisfies both.
    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(token, @root, %{action: "write"})

    assert {:error, {:caveat_failed, "action = write"}} =
             CapabilityToken.authorize(token, @root, %{action: "read"})
  end

  # -------------------------------------------------------
  # Signature integrity
  # -------------------------------------------------------

  test "wrong root key yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "u")
    assert {:error, :invalid_signature} = CapabilityToken.authorize(token, "other-key", %{})
  end

  test "tokens do not cross-verify between root keys" do
    a = attenuate!(CapabilityToken.mint("key-a", "u"), "action = read")
    b = attenuate!(CapabilityToken.mint("key-b", "u"), "action = read")

    assert :ok = CapabilityToken.authorize(a, "key-a", %{action: "read"})
    assert :ok = CapabilityToken.authorize(b, "key-b", %{action: "read"})
    assert {:error, :invalid_signature} = CapabilityToken.authorize(a, "key-b", %{action: "read"})
    assert {:error, :invalid_signature} = CapabilityToken.authorize(b, "key-a", %{action: "read"})
  end

  test "flipping a signature byte yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "u")
    {id, caveats, <<head::binary-size(31), last::8>>} = raw(token)
    forged = pack(id, caveats, <<head::binary, Bitwise.bxor(last, 1)::8>>)

    assert {:error, :invalid_signature} = CapabilityToken.authorize(forged, @root, %{})
  end

  test "stripping a caveat while keeping the signature yields :invalid_signature" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("expires_at = 100")

    {id, caveats, sig} = raw(token)
    assert length(caveats) == 2

    # Drop the expiry caveat but keep the final signature — the classic
    # macaroon attack. The chain no longer recomputes.
    stripped = pack(id, ["action = read"], sig)
    assert {:error, :invalid_signature} = CapabilityToken.authorize(stripped, @root, %{now: 999})

    # Dropping every caveat is equally hopeless.
    bare = pack(id, [], sig)
    assert {:error, :invalid_signature} = CapabilityToken.authorize(bare, @root, %{now: 999})
  end

  test "editing a caveat's text yields :invalid_signature" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")
    {id, _caveats, sig} = raw(token)

    widened = pack(id, ["action = admn"], sig)

    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(widened, @root, %{action: "admn"})
  end

  test "reordering caveats yields :invalid_signature" do
    token =
      @root
      |> CapabilityToken.mint("u")
      |> attenuate!("action = read")
      |> attenuate!("resource_prefix = /docs/")

    {id, [c1, c2], sig} = raw(token)
    swapped = pack(id, [c2, c1], sig)

    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(swapped, @root, %{action: "read", resource: "/docs/x"})
  end

  test "swapping the identifier yields :invalid_signature" do
    token = CapabilityToken.mint(@root, "user:1")
    {_id, caveats, sig} = raw(token)
    forged = pack("user:2", caveats, sig)

    assert {:error, :invalid_signature} = CapabilityToken.authorize(forged, @root, %{})
  end

  test "signature check precedes caveat evaluation" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 1")

    # Expired AND wrong key -> the signature failure is reported.
    assert {:error, :invalid_signature} =
             CapabilityToken.authorize(token, "wrong-key", %{now: 10_000})
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string is malformed" do
    assert {:error, :malformed} = CapabilityToken.authorize("", @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token("")
    assert {:error, :malformed} = CapabilityToken.attenuate("", "action = read")
  end

  test "non-base64 garbage is malformed" do
    assert {:error, :malformed} = CapabilityToken.authorize("not a token!!!", @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token("not a token!!!")
  end

  test "valid base64 with garbage content is malformed" do
    garbage = Base.url_encode64("nowhere near a token structure", padding: false)
    assert {:error, :malformed} = CapabilityToken.authorize(garbage, @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token(garbage)
    assert {:error, :malformed} = CapabilityToken.attenuate(garbage, "action = read")
  end

  test "a truncated token is malformed" do
    token = attenuate!(CapabilityToken.mint(@root, "user:1"), "action = read")
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = CapabilityToken.authorize(truncated, @root, %{})
  end

  test "a wrong version byte is malformed" do
    token = CapabilityToken.mint(@root, "u")
    {:ok, <<1, rest::binary>>} = Base.url_decode64(token, padding: false)
    bad = Base.url_encode64(<<2, rest::binary>>, padding: false)

    assert {:error, :malformed} = CapabilityToken.authorize(bad, @root, %{})
    assert {:error, :malformed} = CapabilityToken.inspect_token(bad)
  end

  test "a caveat count that disagrees with the body is malformed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")
    {id, caveats, sig} = raw(token)

    # Claim two caveats but supply one.
    body = for c <- caveats, into: <<>>, do: <<byte_size(c)::16, c::binary>>

    bad =
      Base.url_encode64(
        <<1, byte_size(id)::16, id::binary, 2::16, body::binary, sig::binary>>,
        padding: false
      )

    assert {:error, :malformed} = CapabilityToken.authorize(bad, @root, %{})
  end

  test "non-binary and non-map arguments are malformed" do
    token = CapabilityToken.mint(@root, "u")

    assert {:error, :malformed} = CapabilityToken.authorize(:not_a_token, @root, %{})
    assert {:error, :malformed} = CapabilityToken.authorize(token, @root, :not_a_map)
    assert {:error, :malformed} = CapabilityToken.inspect_token(123)
    assert {:error, :malformed} = CapabilityToken.attenuate(token, :read)
  end

  test "empty caveats are rejected by attenuate" do
    token = CapabilityToken.mint(@root, "u")
    assert {:error, :malformed} = CapabilityToken.attenuate(token, "")
  end

  test "over-long caveats are rejected by attenuate" do
    token = CapabilityToken.mint(@root, "u")
    assert {:error, :malformed} = CapabilityToken.attenuate(token, String.duplicate("x", 65_536))
    assert {:ok, _} = CapabilityToken.attenuate(token, String.duplicate("x", 65_535))
  end

  # -------------------------------------------------------
  # Delegation chains
  # -------------------------------------------------------

  test "independent delegations of the same token both verify" do
    base = CapabilityToken.mint(@root, "user:7")
    reader = attenuate!(base, "action = read")
    writer = attenuate!(base, "action = write")

    refute reader == writer
    assert :ok = CapabilityToken.authorize(reader, @root, %{action: "read"})
    assert :ok = CapabilityToken.authorize(writer, @root, %{action: "write"})

    assert {:error, {:caveat_failed, "action = read"}} =
             CapabilityToken.authorize(reader, @root, %{action: "write"})
  end

  test "a long delegation chain still verifies" do
    token =
      Enum.reduce(1..25, CapabilityToken.mint(@root, "u"), fn i, acc ->
        attenuate!(acc, "resource_prefix = " <> String.duplicate("/a", i))
      end)

    ctx = %{resource: String.duplicate("/a", 25) <> "/leaf"}
    assert :ok = CapabilityToken.authorize(token, @root, ctx)
    assert {:ok, %{caveats: caveats}} = CapabilityToken.inspect_token(token)
    assert length(caveats) == 25
  end

  test "expires_at accepts a negative value and rejects a value with trailing garbage" do
    negative = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = -5")

    assert :ok = CapabilityToken.authorize(negative, @root, %{now: -6})

    assert {:error, {:caveat_failed, "expires_at = -5"}} =
             CapabilityToken.authorize(negative, @root, %{now: -5})

    trailing = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100abc")

    assert {:error, {:caveat_failed, "expires_at = 100abc"}} =
             CapabilityToken.authorize(trailing, @root, %{now: 1})
  end

  test "expires_at fails closed when :now is present but not an integer" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "expires_at = 100")

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: 99.0})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: "99"})

    assert {:error, {:caveat_failed, "expires_at = 100"}} =
             CapabilityToken.authorize(token, @root, %{now: nil})
  end

  test "a non-binary root key yields malformed" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "action = read")

    assert {:error, :malformed} = CapabilityToken.authorize(token, :not_a_key, %{action: "read"})
    assert {:error, :malformed} = CapabilityToken.authorize(token, 123, %{action: "read"})
    assert {:error, :malformed} = CapabilityToken.authorize(token, nil, %{action: "read"})
  end

  test "resource_prefix fails closed when :resource is present but not a binary" do
    token = attenuate!(CapabilityToken.mint(@root, "u"), "resource_prefix = /docs/")

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{resource: :"/docs/x"})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{resource: 42})

    assert {:error, {:caveat_failed, "resource_prefix = /docs/"}} =
             CapabilityToken.authorize(token, @root, %{resource: ["/docs/", "x"]})
  end

  test "attenuate rejects a non-binary token" do
    assert {:error, :malformed} = CapabilityToken.attenuate(:not_a_token, "action = read")
    assert {:error, :malformed} = CapabilityToken.attenuate(nil, "action = read")
    assert {:error, :malformed} = CapabilityToken.attenuate(42, "action = read")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
