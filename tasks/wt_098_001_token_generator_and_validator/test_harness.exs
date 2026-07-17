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
    assert {:error, :malformed} = verify("", "secret")
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
end
