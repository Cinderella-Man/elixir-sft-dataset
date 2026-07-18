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