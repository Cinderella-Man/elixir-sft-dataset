    test "returns :not_found for unknown ids", %{server: s} do
      assert {:error, :not_found} = Archive.fetch_node(s, 123)
    end