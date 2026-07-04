  test "supports rows without outer pipes" do
    md = """
    Name | Age
    --- | ---
    Alice | 30
    """

    assert [%{headers: ["Name", "Age"], rows: [%{"Name" => "Alice", "Age" => "30"}]}] = parse(md)
  end