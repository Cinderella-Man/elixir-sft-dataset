  test "bullet lines starting with more than one dash are ignored" do
    md = """
    ## Dashes

    -- **Double**: Two dashes (a)
    - - **Spaced**: Dash space dash (b)
    --- **Triple**: Three dashes (c)
    - **Good**: Single dash (d)
    """

    [%{items: items}] = parse(md)
    assert Enum.map(items, & &1.name) == ["Good"]
    assert hd(items).tags == ["d"]
  end