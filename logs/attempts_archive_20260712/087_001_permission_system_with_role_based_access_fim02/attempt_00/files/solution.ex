  # `:owner` rule — identity check only, role is irrelevant.
  defp check(:owner, _role, opts) do
    owner_id = Keyword.get(opts, :owner_id)
    user_id = Keyword.get(opts, :user_id)

    not is_nil(owner_id) and not is_nil(user_id) and owner_id == user_id
  end

  # Normal role rule — compare ranks, ignore opts.
  defp check(required_role, role, _opts)
       when required_role in @roles and role in @roles do
    rank(role) >= rank(required_role)
  end

  # Unknown role or required_role value — deny.
  defp check(_required_role, _role, _opts), do: false