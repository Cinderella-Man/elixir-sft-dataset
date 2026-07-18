  test "tampered token returns :invalid_signature", %{server: server} do
    token = SingleUseToken.issue(server, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = SingleUseToken.redeem(server, tampered)
  end