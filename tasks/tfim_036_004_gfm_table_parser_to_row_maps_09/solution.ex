  test "ignores surrounding prose and blank lines" do
    md = """
    Some intro text.

    | A | B |
    | --- | --- |
    | 1 | 2 |

    Trailing note.
    """

    assert [%{headers: ["A", "B"], rows: [%{"A" => "1", "B" => "2"}]}] = parse(md)
  end