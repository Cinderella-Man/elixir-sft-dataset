  test "bullet lines not matching the bold-name format are ignored" do
    md = """
    ## Misc

    - just a plain bullet
    - **Good**: Proper item (tag)
    - another bad bullet (fake, tags)
    """

    [%{items: items}] = parse(md)
    assert length(items) == 1
    assert hd(items).name == "Good"
  end