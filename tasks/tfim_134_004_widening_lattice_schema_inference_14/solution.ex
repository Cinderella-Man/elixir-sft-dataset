  test "headers: false generates positional names" do
    csv = """
    2020-01-15,1
    2020-01-15T10:00:00,2
    """

    assert schema(csv, headers: false) == %{
             "column_1" => :datetime,
             "column_2" => :integer
           }
  end