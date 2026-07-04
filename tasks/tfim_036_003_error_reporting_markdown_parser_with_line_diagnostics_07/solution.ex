  test "space-indented nested bullets are silently ignored, not reported" do
    md = """
    ## H
    - **Parent**: top (a)
      - **Child**: indented (b)
    """

    %{categories: [%{items: items}], errors: errors} = parse(md)
    assert Enum.map(items, & &1.name) == ["Parent"]
    assert errors == []
  end