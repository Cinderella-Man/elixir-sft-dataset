  test "masks sensitive keys in a keyword list", %{m: m} do
    data = [username: "dave", password: "secret!", role: :viewer]
    result = LogMasker.mask(m, data)
    assert result[:username] == "dave"
    assert result[:password] == "[MASKED]"
    assert result[:role] == :viewer
  end