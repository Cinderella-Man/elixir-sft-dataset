  test "preserves record order under concurrent processing", %{pid: pid} do
    records = for i <- 1..50, do: %{name: "user#{i}", id: i}
    result = Anonymizer.anonymize(pid, records)
    assert Enum.map(result, & &1.id) == Enum.to_list(1..50)
  end