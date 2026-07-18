  test "plain lists of maps and keyword lists are walked element-by-element", %{s: s} do
    result = MaskingServer.mask(s, [%{password: "a", note: "hi"}, [token: "b", user: "eve"]])
    [first, second] = result
    assert first.password == "[MASKED]"
    assert first.note == "hi"
    assert second[:token] == "[MASKED]"
    assert second[:user] == "eve"
  end