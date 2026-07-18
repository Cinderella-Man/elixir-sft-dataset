  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = TransactionAnalyzer.analyze("/no/such/file/ever.jsonl")
  end