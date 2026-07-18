  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = MetricAggregator.summarize("/no/such/file/ever.jsonl")
  end