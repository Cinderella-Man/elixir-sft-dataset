  test "fake yields a deterministic fabricated string for every value" do
    values = ["Dave", "Carol", "Alice", "Bob"]
    records = [%{names: values}]

    [r1] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})
    [r2] = Anonymizer.anonymize(records, %{"names[]" => {:fake, "s"}})

    assert r1.names == r2.names
    assert length(r1.names) == length(values)

    for {original, fake} <- Enum.zip(values, r1.names) do
      assert is_binary(fake)
      assert fake != ""
      assert fake != original
    end
  end