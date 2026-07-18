  @doc """
  Produces maps representing a user domain model.

  ## Shape

      %{
        id:    pos_integer(),
        name:  String.t(),   # letters only, 1–50 chars
        email: String.t(),   # "<local>@<domain>.<tld>"
        age:   integer(),    # 18–120
        role:  :admin | :editor | :viewer
      }

  All constraints are enforced inside the generator; consumers never need to
  call `StreamData.filter/2` to discard values.
  """
  @spec user() :: StreamData.t(map())
  def user do
    SD.fixed_map(%{
      id: SD.positive_integer(),
      name: user_name(),
      email: email(),
      age: SD.integer(18..120),
      role: SD.member_of([:admin, :editor, :viewer])
    })
  end