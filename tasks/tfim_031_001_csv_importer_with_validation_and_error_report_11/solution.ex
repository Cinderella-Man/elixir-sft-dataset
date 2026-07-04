  test "boolean field accepts true, false, 1, 0 case-insensitively" do
    csv = """
    name,email,age,active
    A,a@b.com,1,TRUE
    B,b@b.com,2,False
    C,c@b.com,3,0
    D,d@b.com,4,1
    """

    assert {:ok, valid, []} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 4
  end