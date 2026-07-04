  test "unique_tags collects distinct values per key", %{report: r} do
    assert MapSet.equal?(r.unique_tags["host"], MapSet.new(["a", "b", "c"]))
    assert MapSet.equal?(r.unique_tags["region"], MapSet.new(["us", "eu"]))
  end