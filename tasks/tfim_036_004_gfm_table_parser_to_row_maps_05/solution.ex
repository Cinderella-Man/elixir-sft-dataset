  test "pads ragged rows that have too few cells" do
    md = """
    | Name | Age |
    | --- | --- |
    | Bob |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"Name" => "Bob", "Age" => ""}
  end