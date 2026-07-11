  test "quoted numbers are strings and their repetition breaks uniqueness" do
    csv = """
    code
    "1"
    "1"
    """

    assert schema(csv) == %{"code" => %{type: :string, nullable: false, unique: false}}
  end