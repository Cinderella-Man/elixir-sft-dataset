  test "headers: false generates positional column names" do
    csv = """
    1,2.5
    3,4.5
    """

    assert schema(csv, headers: false) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end