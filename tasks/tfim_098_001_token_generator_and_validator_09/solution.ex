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