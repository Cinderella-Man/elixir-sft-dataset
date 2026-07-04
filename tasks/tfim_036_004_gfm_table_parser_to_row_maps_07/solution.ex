  test "escaped pipes do not split cells" do
    md = """
    | Expr | Note |
    | --- | --- |
    | a \\| b | logical or |
    """

    [%{rows: [row]}] = parse(md)
    assert row == %{"Expr" => "a | b", "Note" => "logical or"}
  end