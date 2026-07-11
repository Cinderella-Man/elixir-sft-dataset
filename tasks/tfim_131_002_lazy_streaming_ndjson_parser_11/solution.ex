  test "decode_line/1 decodes and reports errors without raising" do
    assert NdjsonStreamer.decode_line(~s({"id":1})) == {:ok, %{"id" => 1}}
    assert NdjsonStreamer.decode_line("  42  ") == {:ok, 42}
    assert NdjsonStreamer.decode_line("nope") == {:error, {:invalid_json, "nope"}}
  end