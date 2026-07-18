  test "from_schema/1 returns a %StreamData{} struct for every schema form" do
    schemas = [
      :integer,
      {:integer, 1, 2},
      :boolean,
      :string,
      {:string, 0, 2},
      {:enum, [:a, :b]},
      {:list, :boolean},
      {:list, :boolean, []},
      {:map, %{a: :integer}},
      {:optional, :integer},
      {:one_of, [:integer, :boolean]}
    ]

    for schema <- schemas do
      assert %StreamData{} = SchemaGenerators.from_schema(schema)
    end
  end