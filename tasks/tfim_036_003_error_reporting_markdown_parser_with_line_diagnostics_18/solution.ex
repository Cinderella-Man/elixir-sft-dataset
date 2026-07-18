  test "blank lines and arbitrary prose produce no errors" do
    md = """
    ## H

    Some introductory prose.
    Another paragraph mentioning - a dash mid-sentence.

    - **i**: d (a)

    Closing prose.
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)

    assert Enum.map(items, & &1.name) == ["i"]
    assert errors == []
  end