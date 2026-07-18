  test "a non-pipe line ends the table and later pipe rows are excluded" do
    md = """
    | A |
    | --- |
    | 1 |
    prose interrupts here
    | 2 |
    """

    assert parse(md) == [%{headers: ["A"], alignments: [:none], rows: [%{"A" => "1"}]}]
  end