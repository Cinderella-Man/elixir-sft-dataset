  test "header row with no data rows is non-nullable and unique" do
    csv = """
    a,b,c
    """

    assert schema(csv) == %{
             "a" => %{type: :string, nullable: false, unique: true},
             "b" => %{type: :string, nullable: false, unique: true},
             "c" => %{type: :string, nullable: false, unique: true}
           }
  end