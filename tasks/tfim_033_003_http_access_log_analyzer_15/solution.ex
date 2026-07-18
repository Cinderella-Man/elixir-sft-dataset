  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = AccessLogAnalyzer.analyze("/no/such/file/ever.jsonl")
  end