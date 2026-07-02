  test "infers basic column types" do
    csv = """
    name,age,height,active,birth,created
    Alice,30,5.5,true,2020-01-15,2020-01-15T10:30:00
    Bob,25,6.0,false,1999-12-31,1999-12-31T08:00:00
    """

    assert schema(csv) == %{
             "name" => :string,
             "age" => :integer,
             "height" => :float,
             "active" => :boolean,
             "birth" => :date,
             "created" => :datetime
           }
  end