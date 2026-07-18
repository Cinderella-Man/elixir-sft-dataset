  test "UserView v2 render returns exactly the four documented fields" do
    user = %{
      first_name: "Zed",
      last_name: "Quinn",
      email: "zed@example.com",
      created_at: "2025-02-02T09:00:00Z"
    }

    assert LifecycleApi.Views.UserView.render("v2", user) == %{
             first_name: "Zed",
             last_name: "Quinn",
             email: "zed@example.com",
             created_at: "2025-02-02T09:00:00Z"
           }
  end