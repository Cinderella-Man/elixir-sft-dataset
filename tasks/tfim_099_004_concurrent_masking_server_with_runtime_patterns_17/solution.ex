  test "server started without :sensitive_keys masks no keys at all" do
    d = start_supervised!({MaskingServer, []}, id: :default_opts_server)
    result = MaskingServer.mask(d, %{password: "hunter2", token: "abc"})
    assert result.password == "hunter2"
    assert result.token == "abc"
    assert MaskingServer.stats(d).keys_masked == 0
  end