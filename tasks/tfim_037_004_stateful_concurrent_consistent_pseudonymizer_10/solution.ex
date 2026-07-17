  test "mapping/2 keys are the original values, not stringified copies", %{pid: pid} do
    Anonymizer.anonymize(pid, [%{name: 42}])
    mapping = Anonymizer.mapping(pid, :name)
    assert Map.has_key?(mapping, 42)
    assert mapping[42] =~ ~r/^PERSON_\d+$/
  end