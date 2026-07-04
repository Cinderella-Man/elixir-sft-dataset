  test "distinct values get distinct pseudonyms under concurrent load", %{pid: pid} do
    records = for i <- 1..200, do: %{name: "name_#{i}"}
    result = Anonymizer.anonymize(pid, records)
    pseudonyms = Enum.map(result, & &1.name)
    assert length(Enum.uniq(pseudonyms)) == 200
  end