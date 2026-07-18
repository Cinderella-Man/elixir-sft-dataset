  test "error content has trailing whitespace trimmed off the original line" do
    md = "## H\n- broken bullet   \n###  Deep   \n"

    %{errors: errors} = parse(md)

    assert errors == [
             %{line: 2, content: "- broken bullet", reason: :malformed_item},
             %{line: 3, content: "###  Deep", reason: :unsupported_heading}
           ]
  end