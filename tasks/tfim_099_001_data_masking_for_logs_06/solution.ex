  test "recursively masks nested maps", %{m: m} do
    data = %{
      user: %{
        name: "carol",
        credentials: %{password: "hunter2", token: "tok_xyz"}
      }
    }

    result = LogMasker.mask(m, data)
    assert result.user.name == "carol"
    assert result.user.credentials.password == "[MASKED]"
    assert result.user.credentials.token == "[MASKED]"
  end