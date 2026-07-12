  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u) do
    %{first_name: u.first_name, last_name: u.last_name, email: u.email, created_at: u.created_at}
  end
