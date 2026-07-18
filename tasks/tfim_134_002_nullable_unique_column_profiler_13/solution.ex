  test "a quoted field keeps its comma instead of splitting into another column" do
    csv = ~s("x,y",1\n"x,z",2\n)

    assert schema(csv, headers: false) == %{
             "column_1" => %{type: :string, nullable: false, unique: true},
             "column_2" => %{type: :integer, nullable: false, unique: true}
           }
  end