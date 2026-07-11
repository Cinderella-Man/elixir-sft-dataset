  test "duplicate nulls do not break uniqueness of the non-null values" do
    csv = """
    n
    1
    ,
    2
    """

    # second data row: n is empty (null), ignored for both type and uniqueness
    assert schema(csv) == %{"n" => %{type: :integer, nullable: true, unique: true}}
  end