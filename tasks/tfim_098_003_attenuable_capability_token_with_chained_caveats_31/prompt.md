# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CapabilityToken do
  @moduledoc """
  Attenuable, macaroon-style capability tokens.

  A token is a self-contained, URL-safe binary that names a capability (an
  *identifier*) and carries an ordered list of *caveats* narrowing what the
  bearer may do. Anyone holding a token can **narrow** it offline — appending a
  caveat requires no key — but nobody can **widen** it: dropping, reordering or
  editing a caveat would require walking the HMAC chain backwards, which is
  infeasible without the root key.

  ## Wire format

  All integers are big-endian unsigned. The decoded binary is:

      <<1,                              # version byte
        id_size::16, identifier::binary-size(id_size),
        caveat_count::16,
        # caveat_count repetitions of <<len::16, caveat::binary-size(len)>>
        signature::binary-32>>

  and the token itself is that binary under `Base.url_encode64/2` with
  `padding: false`.

  ## Signature chain

      sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
      sig_i = :crypto.mac(:hmac, :sha256, sig_(i-1), caveat_i)

  Only the final signature travels with the token. `authorize/3` recomputes the
  whole chain from the root key and compares in constant time.

  ## Caveat language

  A caveat is `"key = value"` (the first `" = "` separates; the value may itself
  contain spaces or `=`). Three keys are recognized:

    * `"expires_at = <integer>"` — needs integer `context[:now]`, satisfied iff
      `now < integer` (strictly).
    * `"action = <string>"` — satisfied iff `context[:action] == <string>`.
    * `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is a
      binary starting with `<string>`.

  Anything else fails closed: unknown keys, malformed caveats, non-integer
  expiries and missing context keys are all *not satisfied*.
  """

  @version 1
  @sig_size 32
  @max_caveat_size 65_535

  @type token :: binary()
  @type caveat :: binary()
  @type context :: %{optional(atom()) => term()}
  @type reason :: :malformed | :invalid_signature | {:caveat_failed, caveat()}

  @doc """
  Mints a fresh token for `identifier`, signed with `root_key` and carrying no
  caveats.

  Returns the URL-safe token binary.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> CapabilityToken.inspect_token(token)
      {:ok, %{identifier: "user:42", caveats: []}}
  """
  @spec mint(binary(), binary()) :: token()
  def mint(root_key, identifier) when is_binary(root_key) and is_binary(identifier) do
    signature = :crypto.mac(:hmac, :sha256, root_key, identifier)
    encode(identifier, [], signature)
  end

  @doc """
  Appends `caveat` to `token` without needing the root key.

  Returns `{:ok, new_token}` whose caveats are the old ones, in order, followed
  by `caveat`. Returns `{:error, :malformed}` if `token` is not decodable, if
  either argument is not a binary, or if `caveat` is empty or longer than
  #{@max_caveat_size} bytes. The original token is untouched.
  """
  @spec attenuate(token(), caveat()) :: {:ok, token()} | {:error, :malformed}
  def attenuate(token, caveat)
      when is_binary(token) and is_binary(caveat) and byte_size(caveat) in 1..@max_caveat_size do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      new_signature = :crypto.mac(:hmac, :sha256, signature, caveat)
      {:ok, encode(identifier, caveats ++ [caveat], new_signature)}
    end
  end

  def attenuate(_token, _caveat), do: {:error, :malformed}

  @doc """
  Decodes a token without any key and **without verifying the signature**.

  Returns `{:ok, %{identifier: identifier, caveats: caveats}}` with the caveats
  in attachment order, or `{:error, :malformed}`. This is a debugging helper: it
  makes no authenticity claim at all.
  """
  @spec inspect_token(token()) ::
          {:ok, %{identifier: binary(), caveats: [caveat()]}} | {:error, :malformed}
  def inspect_token(token) when is_binary(token) do
    with {:ok, identifier, caveats, _signature} <- decode(token) do
      {:ok, %{identifier: identifier, caveats: caveats}}
    end
  end

  def inspect_token(_token), do: {:error, :malformed}

  @doc """
  Authorizes `token` under `root_key` for the request described by `context`.

  Returns `:ok` when the signature chain verifies *and* every caveat is
  satisfied. Checks run in this order:

    1. structural decode — `{:error, :malformed}`;
    2. signature chain — `{:error, :invalid_signature}`;
    3. caveats, in attachment order — `{:error, {:caveat_failed, caveat}}` for
       the first unsatisfied one (later caveats are not evaluated).

  Signature verification always precedes caveat evaluation, so a token that is
  both expired and forged reports `:invalid_signature`.
  """
  @spec authorize(token(), binary(), context()) :: :ok | {:error, reason()}
  def authorize(token, root_key, context)
      when is_binary(token) and is_binary(root_key) and is_map(context) do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      expected = chain(root_key, identifier, caveats)

      if secure_compare(expected, signature) do
        check_caveats(caveats, context)
      else
        {:error, :invalid_signature}
      end
    end
  end

  def authorize(_token, _root_key, _context), do: {:error, :malformed}

  # --- encoding -------------------------------------------------------------

  @spec encode(binary(), [caveat()], binary()) :: token()
  defp encode(identifier, caveats, signature) do
    body =
      for caveat <- caveats, into: <<>> do
        <<byte_size(caveat)::16, caveat::binary>>
      end

    binary =
      <<@version, byte_size(identifier)::16, identifier::binary, length(caveats)::16,
        body::binary, signature::binary-size(@sig_size)>>

    Base.url_encode64(binary, padding: false)
  end

  @spec decode(binary()) :: {:ok, binary(), [caveat()], binary()} | {:error, :malformed}
  defp decode(token) do
    with {:ok, binary} <- Base.url_decode64(token, padding: false),
         <<@version, id_size::16, identifier::binary-size(id_size), count::16, rest::binary>> <-
           binary,
         {:ok, caveats, <<signature::binary-size(@sig_size)>>} <- take_caveats(count, rest, []) do
      {:ok, identifier, caveats, signature}
    else
      _other -> {:error, :malformed}
    end
  end

  @spec take_caveats(non_neg_integer(), binary(), [caveat()]) ::
          {:ok, [caveat()], binary()} | :error
  defp take_caveats(0, rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp take_caveats(count, <<len::16, caveat::binary-size(len), rest::binary>>, acc)
       when count > 0 do
    take_caveats(count - 1, rest, [caveat | acc])
  end

  defp take_caveats(_count, _rest, _acc), do: :error

  # --- signatures -----------------------------------------------------------

  @spec chain(binary(), binary(), [caveat()]) :: binary()
  defp chain(root_key, identifier, caveats) do
    Enum.reduce(caveats, :crypto.mac(:hmac, :sha256, root_key, identifier), fn caveat, sig ->
      :crypto.mac(:hmac, :sha256, sig, caveat)
    end)
  end

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  # --- caveats --------------------------------------------------------------

  @spec check_caveats([caveat()], context()) :: :ok | {:error, {:caveat_failed, caveat()}}
  defp check_caveats([], _context), do: :ok

  defp check_caveats([caveat | rest], context) do
    if satisfied?(caveat, context) do
      check_caveats(rest, context)
    else
      {:error, {:caveat_failed, caveat}}
    end
  end

  @spec satisfied?(caveat(), context()) :: boolean()
  defp satisfied?(caveat, context) do
    case :binary.split(caveat, " = ") do
      [key, value] -> satisfied?(key, value, context)
      _other -> false
    end
  end

  @spec satisfied?(binary(), binary(), context()) :: boolean()
  defp satisfied?("expires_at", value, context) do
    with {:ok, limit} <- parse_integer(value),
         now when is_integer(now) <- Map.get(context, :now) do
      now < limit
    else
      _other -> false
    end
  end

  defp satisfied?("action", value, context), do: Map.get(context, :action) === value

  defp satisfied?("resource_prefix", value, context) do
    case Map.get(context, :resource) do
      resource when is_binary(resource) -> String.starts_with?(resource, value)
      _other -> false
    end
  end

  defp satisfied?(_key, _value, _context), do: false

  @spec parse_integer(binary()) :: {:ok, integer()} | :error
  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
