  test "parses multiple categories in document order" do
    md = """
    ## Fruits

    - **Apple**: A red fruit (sweet, crunchy)

    ## Vegetables

    - **Carrot**: An orange vegetable (savory, crunchy)
    """

    result = parse(md)
    assert length(result) == 2
    assert Enum.at(result, 0).category == "Fruits"
    assert Enum.at(result, 1).category == "Vegetables"
  end