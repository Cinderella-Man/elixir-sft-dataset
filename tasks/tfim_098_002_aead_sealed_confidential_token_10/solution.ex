  test "tampered token returns :invalid" do
    token = seal(%{role: "user"}, @key, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid} = open(tampered, @key)
  end