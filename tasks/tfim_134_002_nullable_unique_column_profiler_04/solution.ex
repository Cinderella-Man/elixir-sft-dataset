  test "unique is false when non-null values repeat" do
    csv = """
    n
    1
    2
    2
    """

    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: false}}
  end