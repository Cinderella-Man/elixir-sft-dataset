  test "UserView v1 render returns exactly the joined name and the email" do
    user = %{
      first_name: "Zed",
      last_name: "Quinn",
      email: "zed@example.com",
      created_at: "2025-02-02T09:00:00Z"
    }

    assert LifecycleApi.Views.UserView.render("v1", user) ==
             %{name: "Zed Quinn", email: "zed@example.com"}
  end