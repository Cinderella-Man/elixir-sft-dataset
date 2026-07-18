  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = LogAnalyzer.analyze("/no/such/file/ever.log")
  end