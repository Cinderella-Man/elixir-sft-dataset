  test "bullet items before first H2 heading are discarded" do
    md = """
    - **Orphan**: Should be ignored (lost)

    ## Real

    - **Valid**: Kept (yes)
    """

    result = parse(md)
    assert length(result) == 1
    assert hd(result).category == "Real"
    assert length(hd(result).items) == 1
  end