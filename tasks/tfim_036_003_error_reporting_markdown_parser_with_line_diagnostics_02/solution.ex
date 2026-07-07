  test "clean document has no errors" do
    md = """
    ## Tools

    - **Hammer**: Drives nails (hardware, manual)
    """

    assert parse(md) == %{
             categories: [
               %{
                 category: "Tools",
                 items: [
                   %{name: "Hammer", description: "Drives nails", tags: ["hardware", "manual"]}
                 ]
               }
             ],
             errors: []
           }
  end