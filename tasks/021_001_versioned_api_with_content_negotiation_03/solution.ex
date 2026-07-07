  def render(version, user) do
    case version do
      "v1" ->
        %{name: user.first_name <> " " <> user.last_name, email: user.email}

      "v2" ->
        %{
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,
          created_at: user.created_at
        }
    end
  end