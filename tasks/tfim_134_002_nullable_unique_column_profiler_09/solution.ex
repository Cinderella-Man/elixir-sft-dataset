  test "integer/float promotion still applies to the type" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => %{type: :float, nullable: false, unique: true}}
  end