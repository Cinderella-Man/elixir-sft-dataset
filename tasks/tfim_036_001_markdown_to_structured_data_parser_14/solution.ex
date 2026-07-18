  test "H3 and deeper headings are ignored mid-document" do
    md = """
    ## Real

    - **Item**: Desc (t)

    ### Not a category

    - **Also**: Under real still? (maybe)
    """

    # H3 is ignored, so "Also" bullet may either be attributed to "Real"
    # or dropped — either way, "Not a category" must NOT appear as a category.
    result = parse(md)
    category_names = Enum.map(result, & &1.category)
    refute "Not a category" in category_names
  end