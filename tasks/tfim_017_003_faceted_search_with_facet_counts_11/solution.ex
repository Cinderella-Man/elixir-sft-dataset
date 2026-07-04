  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             Faceted.search(products(), %{"sort" => "inserted_at"})
  end