  test "handles CRLF line endings" do
    md = "| A | B |\r\n| --- | --- |\r\n| 1 | 2 |\r\n"
    assert [%{headers: ["A", "B"], rows: [%{"A" => "1", "B" => "2"}]}] = parse(md)
  end