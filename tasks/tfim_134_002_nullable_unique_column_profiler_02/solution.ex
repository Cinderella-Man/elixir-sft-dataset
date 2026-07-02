  test "infers type, nullability, and uniqueness together" do
    csv = """
    name,age
    Alice,30
    Bob,25
    """

    assert schema(csv) == %{
             "name" => %{type: :string, nullable: false, unique: true},
             "age" => %{type: :integer, nullable: false, unique: true}
           }
  end