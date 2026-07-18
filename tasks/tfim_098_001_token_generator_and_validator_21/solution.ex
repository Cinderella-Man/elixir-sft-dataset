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