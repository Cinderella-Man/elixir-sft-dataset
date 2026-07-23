# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule SecureToken do
  @moduledoc """
  Stateless, signed, expiring tokens backed by HMAC-SHA256.

  Tokens are self-contained: they carry the payload, issue time, and
  expiry time, all covered by a MAC computed with the caller's secret.
  No database or persistent state is required to verify them.

  ## Wire format

  The decoded binary (before base64) has the layout:

      <<issued_at::signed-64, expires_at::signed-64,
        payload_size::unsigned-32, payload::binary, mac::binary-32>>

  where `payload` is `:erlang.term_to_binary/1` output and `mac` is
  `HMAC-SHA256(secret, issued_at || expires_at || payload_size || payload)`.
  The whole thing is then `Base.url_encode64/2` without padding.

  ## Clock injection

  Both `generate/4` and `verify/3` accept an optional `:clock` keyword
  whose value is a zero-arity function returning a Unix epoch second.
  When omitted, `System.os_time(:second)` is used. This is primarily a
  test seam — in production you should let the default apply.
  """

  import Bitwise

  @hmac_size 32

  @type token :: binary()
  @type reason :: :expired | :invalid_signature | :malformed
  @type opts :: [clock: (-> integer())]

  @doc """
  Generate a signed token for `payload` that expires in `ttl_seconds`.
  """
  @spec generate(term(), binary(), pos_integer(), opts()) :: token()
  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32,
        payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)

    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  @doc """
  Verify and decode a token.

  Returns `{:ok, payload}` if the signature is valid and the token has not
  expired. Otherwise returns one of:

    * `{:error, :invalid_signature}` — structure is readable, HMAC doesn't match
    * `{:error, :expired}`           — signature is valid, token is past its expiry
    * `{:error, :malformed}`         — bad base64, too short, corrupted structure, etc.

  The signature is always checked before expiry, so a valid-structure but
  wrong-secret token that also happens to be past its expiry returns
  `:invalid_signature`, never `:expired`.
  """
  @spec verify(token(), binary(), opts()) :: {:ok, term()} | {:error, reason()}
  def verify(token, secret, opts \\ [])

  def verify(token, secret, opts) when is_binary(token) and is_binary(secret) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _secret, _opts), do: {:error, :malformed}

  # --- internal helpers ---------------------------------------------------

  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp decode_base64(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :malformed}
    end
  end

  # Too short to even contain an HMAC → malformed.
  defp split_mac(binary) when byte_size(binary) < @hmac_size do
    {:error, :malformed}
  end

  defp split_mac(binary) do
    data_size = byte_size(binary) - @hmac_size
    <<data::binary-size(^data_size), mac::binary-size(@hmac_size)>> = binary
    {:ok, data, mac}
  end

  # Structural parse runs before MAC verification so that genuinely
  # corrupted bytes (too-short header, payload_size not matching the
  # remaining binary) come back as :malformed rather than being
  # reported as signature failures. An attacker who knows the key can
  # of course still produce a parseable-but-expired token — but that
  # path is governed by verify_mac/check_expiry, not by this function.
  defp parse_data(
         <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32, rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, issued_at, expires_at, rest}
  end

  defp parse_data(_), do: {:error, :malformed}

  defp verify_mac(secret, data, mac) do
    expected = :crypto.mac(:hmac, :sha256, secret, data)

    if constant_time_equal?(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # A token is expired when the current wall-clock time has reached or
  # passed `expires_at`. Strict `<` means that at exactly the TTL
  # boundary (now == issued_at + ttl) the token is already expired.
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at do
      :ok
    else
      {:error, :expired}
    end
  end

  # [:safe] prevents decoding of terms that could allocate new atoms or
  # function references — standard hygiene for untrusted binaries even
  # after MAC verification.
  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time equality check over two equal-length binaries. Avoids
  # short-circuiting on the first differing byte, which would otherwise
  # let a careful attacker probe the MAC one byte at a time.
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp constant_time_equal?(_, _), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SecureTokenTest do
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

  # We allow SecureToken to accept an optional :clock function so tests
  # can control time. In production it falls back to System.os_time(:second).
  defp generate(payload, secret, ttl),
    do: SecureToken.generate(payload, secret, ttl, clock: &Clock.now/0)

  defp verify(token, secret),
    do: SecureToken.verify(token, secret, clock: &Clock.now/0)

  setup do
    start_supervised!({Clock, 1_000_000})
    :ok
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "generated token verifies successfully" do
    token = generate(%{user_id: 42}, "secret", 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = verify(token, "secret")
  end

  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = generate(payload, "my-secret", 60)
    assert {:ok, ^payload} = verify(token, "my-secret")
  end

  test "token is URL-safe (no +, /, or = characters)" do
    token = generate("hello", "key", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry" do
    token = generate("data", "s3cr3t", 100)
    Clock.advance(99)
    assert {:ok, "data"} = verify(token, "s3cr3t")
  end

  test "expired token returns :expired" do
    token = generate("data", "s3cr3t", 100)
    Clock.advance(101)
    assert {:error, :expired} = verify(token, "s3cr3t")
  end

  test "token expires exactly at ttl boundary" do
    token = generate("data", "s3cr3t", 50)
    Clock.advance(50)
    # At exactly ttl seconds the token should be expired (issued_at + ttl <= now)
    assert {:error, :expired} = verify(token, "s3cr3t")
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "wrong secret returns :invalid_signature" do
    token = generate("payload", "correct-secret", 300)
    assert {:error, :invalid_signature} = verify(token, "wrong-secret")
  end

  test "tampered payload returns :invalid_signature" do
    token = generate(%{role: "user"}, "secret", 300)

    # Flip a character somewhere in the middle of the token
    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = verify(tampered, "secret")
  end

  test "signature check takes precedence over expiry check" do
    # Generate a token that is already expired
    token = generate("old", "secret", 1)
    Clock.advance(200)

    # Even though it's expired, a wrong secret should give :invalid_signature
    assert {:error, :invalid_signature} = verify(token, "bad-secret")
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed" do
    # TODO
  end

  test "random binary returns :malformed" do
    assert {:error, :malformed} = verify("notavalidtoken!!!", "secret")
  end

  test "truncated token returns :malformed" do
    token = generate("hello", "secret", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = verify(truncated, "secret")
  end

  test "valid base64 but garbage content returns :malformed" do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = verify(garbage, "secret")
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "tokens are not cross-verifiable across secrets" do
    t1 = generate("msg", "secret-a", 300)
    t2 = generate("msg", "secret-b", 300)

    assert {:ok, "msg"} = verify(t1, "secret-a")
    assert {:ok, "msg"} = verify(t2, "secret-b")

    assert {:error, :invalid_signature} = verify(t1, "secret-b")
    assert {:error, :invalid_signature} = verify(t2, "secret-a")
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload" do
    token = generate(:hello, "s", 60)
    assert {:ok, :hello} = verify(token, "s")
  end

  test "supports integer payload" do
    token = generate(12345, "s", 60)
    assert {:ok, 12345} = verify(token, "s")
  end

  test "supports list payload" do
    token = generate([1, "two", :three], "s", 60)
    assert {:ok, [1, "two", :three]} = verify(token, "s")
  end

  test "supports deeply nested map payload" do
    payload = %{a: %{b: %{c: "deep"}}}
    token = generate(payload, "s", 60)
    assert {:ok, ^payload} = verify(token, "s")
  end

  test "non-binary token or non-binary secret returns :malformed" do
    assert {:error, :malformed} = verify(nil, "secret")
    assert {:error, :malformed} = verify(12_345, "secret")
    assert {:error, :malformed} = verify(:not_a_token, "secret")
    assert {:error, :malformed} = verify(["list"], "secret")

    token = generate("data", "secret", 300)
    assert {:error, :malformed} = verify(token, :not_a_secret)
    assert {:error, :malformed} = verify(token, 999)
  end

  test "payload rejected by the :safe deserializer returns :malformed" do
    # Hand-rolled ATOM_UTF8_EXT encoding of an atom that has never been
    # created in this VM. `binary_to_term/2` with [:safe] refuses to invent
    # the atom, so the post-HMAC deserialization step must fail. The name is
    # only ever handled as a string here, so the atom stays non-existent.
    name = "secure_token_atom_that_never_existed_ff01"
    unsafe_payload = <<131, 118, byte_size(name)::unsigned-16, name::binary>>

    # Sanity-check the premise of this test: [:safe] really does reject it.
    assert_raise ArgumentError, fn ->
      :erlang.binary_to_term(unsafe_payload, [:safe])
    end

    # Mint a genuine token whose serialized payload has exactly the same
    # size, splice the unsafe bytes over it, and re-sign the whole signed
    # region so the MAC still checks out. Everything up to and including the
    # HMAC check must therefore pass, leaving deserialization as the failure.
    placeholder = :binary.copy("P", byte_size(unsafe_payload) - 6)
    placeholder_bytes = :erlang.term_to_binary(placeholder)
    assert byte_size(placeholder_bytes) == byte_size(unsafe_payload)

    token = generate(placeholder, "secret", 300)
    assert is_binary(token)
    {:ok, decoded} = Base.url_decode64(token, padding: false)
    data = binary_part(decoded, 0, byte_size(decoded) - 32)

    {offset, len} = :binary.match(data, placeholder_bytes)
    tail_size = byte_size(data) - offset - len

    forged_data =
      binary_part(data, 0, offset) <>
        unsafe_payload <> binary_part(data, offset + len, tail_size)

    forged_mac = :crypto.mac(:hmac, :sha256, "secret", forged_data)
    forged = Base.url_encode64(<<forged_data::binary, forged_mac::binary>>, padding: false)

    assert {:error, :malformed} = verify(forged, "secret")
  end

  test "header length prefix disagreeing with remaining bytes is malformed not invalid_signature" do
    token = generate("payload-data", "secret", 300)
    {:ok, decoded} = Base.url_decode64(token, padding: false)
    data_size = byte_size(decoded) - 32
    data = binary_part(decoded, 0, data_size)
    mac = binary_part(decoded, data_size, 32)

    # Drop one byte of signed data: the header now describes more bytes
    # than are present, so the structural parse must fail before the MAC
    # check ever runs (the MAC itself is left intact and now wrong).
    shrunk = binary_part(data, 0, data_size - 1)
    rebuilt = Base.url_encode64(<<shrunk::binary, mac::binary>>, padding: false)

    assert {:error, :malformed} = verify(rebuilt, "secret")
  end

  test "flipping any single byte of the signed region never yields an ok result" do
    token = generate(%{user_id: 7}, "sig-key", 300)
    {:ok, decoded} = Base.url_decode64(token, padding: false)
    data_size = byte_size(decoded) - 32
    total = byte_size(decoded)

    for i <- 0..(data_size - 1) do
      pre = binary_part(decoded, 0, i)
      byte = :binary.at(decoded, i)
      post = binary_part(decoded, i + 1, total - i - 1)
      mutated = <<pre::binary, Bitwise.bxor(byte, 0xFF), post::binary>>
      tampered = Base.url_encode64(mutated, padding: false)

      assert verify(tampered, "sig-key") in [
               {:error, :invalid_signature},
               {:error, :malformed}
             ]
    end
  end

  test "token one byte shorter than the 32-byte HMAC is malformed" do
    short = Base.url_encode64(:binary.copy(<<0>>, 31), padding: false)
    assert {:error, :malformed} = verify(short, "secret")

    # Exactly 32 bytes: an HMAC with no signed data behind it.
    bare_mac = Base.url_encode64(:binary.copy(<<0>>, 32), padding: false)
    assert {:error, :malformed} = verify(bare_mac, "secret")
  end

  # -------------------------------------------------------
  # Default clock (:clock omitted, opts omitted entirely)
  # -------------------------------------------------------

  test "generate/3 and verify/2 work with opts omitted entirely" do
    # The optional opts keyword must genuinely be optional on both calls,
    # and a token minted and checked with the default clock is still live.
    payload = %{sub: "default-arity", scopes: ["read"]}
    token = SecureToken.generate(payload, "default-secret", 300)
    assert is_binary(token)
    assert {:ok, ^payload} = SecureToken.verify(token, "default-secret")

    # An explicitly empty opts list means the same thing as omitting it.
    token2 = SecureToken.generate(payload, "default-secret", 300, [])
    assert {:ok, ^payload} = SecureToken.verify(token2, "default-secret", [])
  end

  test "verify with no clock option reads the real current time for expiry" do
    # Minted far in the past on an injected clock, so under a default clock
    # that reads System.os_time(:second) the token is long expired.
    token = SecureToken.generate("stale", "secret", 60, clock: fn -> 0 end)
    assert {:error, :expired} = SecureToken.verify(token, "secret")
    assert {:error, :expired} = SecureToken.verify(token, "secret", [])

    # A token minted against the real wall clock is accepted by that same
    # default clock, which also pins the default to seconds, not milliseconds.
    fresh =
      SecureToken.generate("fresh", "secret", 300, clock: fn -> System.os_time(:second) end)

    assert {:ok, "fresh"} = SecureToken.verify(fresh, "secret")
  end

  test "generate with no clock option stamps the real current time" do
    reference = System.os_time(:second)
    token = SecureToken.generate("issued-now", "secret", 60)

    # Issued at roughly `reference`, so it is live at that instant...
    assert {:ok, "issued-now"} = SecureToken.verify(token, "secret", clock: fn -> reference end)

    # ...and expired well before an hour later, which would not hold if the
    # issue time were taken from anything other than the current epoch second.
    assert {:error, :expired} =
             SecureToken.verify(token, "secret", clock: fn -> reference + 3_600 end)
  end
end
```
