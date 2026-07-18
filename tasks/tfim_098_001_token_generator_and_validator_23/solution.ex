  test "token one byte shorter than the 32-byte HMAC is malformed" do
    short = Base.url_encode64(:binary.copy(<<0>>, 31), padding: false)
    assert {:error, :malformed} = verify(short, "secret")

    # Exactly 32 bytes: an HMAC with no signed data behind it.
    bare_mac = Base.url_encode64(:binary.copy(<<0>>, 32), padding: false)
    assert {:error, :malformed} = verify(bare_mac, "secret")
  end