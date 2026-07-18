  test "render/3 is a pure downgrade of the canonical document" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v1", "42", user) ==
             %{id: "42", name: "Zoe Lin", email: "zoe@example.com"}
  end