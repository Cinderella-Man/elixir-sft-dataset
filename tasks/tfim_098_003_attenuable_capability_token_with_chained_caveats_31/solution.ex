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