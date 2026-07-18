  test "mask_string replaces a bare SSN pattern in free text" do
    m = FieldMasker.new(%{})
    assert FieldMasker.mask_string(m, "ssn 123-45-6789 ok") == "ssn ***-**-**** ok"
  end