  test "parses multiple items under one category" do
    md = """
    ## Languages

    - **Elixir**: Functional language (fp, concurrent)
    - **Rust**: Systems language (systems, safe)
    - **Python**: Scripting language (scripting, dynamic)
    """

    %{category: "Languages", items: items} = parse(md) |> hd()
    assert length(items) == 3
    assert Enum.map(items, & &1.name) == ["Elixir", "Rust", "Python"]
  end