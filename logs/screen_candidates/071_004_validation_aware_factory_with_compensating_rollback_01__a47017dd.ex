defmodule Factory do
  @moduledoc """
  A small, self-contained test-data factory in the spirit of ExMachina.

  `Factory` knows how to `build/2` structs for named factories (filling in
  sensible sequenced defaults), and to `insert/2`, `insert!/2` them into
  `MyApp.Repo` with explicit validation and *compensating rollback* semantics.

  Every factory declares which fields are **required** (must be non-`nil`).
  When a factory needs an association it does not have an override for, the
  association record is auto-created (persisted) so that its id can be assigned
  to the parent. If the parent later fails validation, those auto-created
  association records are rolled back (deleted) so a failed `insert` leaves the
  repository unchanged.

  Sequences are backed by a single named `Agent` (see `start/0`) so that
  `sequence/2` yields values that are unique across the whole test run, even
  under concurrent (`async: true`) access.

  The struct modules `MyApp.User`, `MyApp.Post` and the `MyApp.Repo` module
  (offering `insert!/1` and `delete!/1`) are provided by the surrounding
  environment; this module only references them.
  """

  @compile {:no_warn_undefined, [MyApp.Repo, MyApp.User, MyApp.Post]}

  @agent __MODULE__.Sequences

  @required %{
    user: [:name, :email],
    post: [:title, :body, :user_id]
  }

  @typedoc "The name of a known factory."
  @type factory_name :: :user | :post

  @typedoc "A keyword list of field overrides applied when building a struct."
  @type overrides :: keyword()

  @doc """
  Starts the named `Agent` that backs the sequence counters.

  Returns the raw `Agent.start_link/2` result. The test suite calls this once
  (typically in `setup_all`) before using any other factory function.
  """
  @spec start() :: Agent.on_start()
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc """
  Builds (without persisting) a struct for `factory_name`.

  A keyword list of `overrides` is merged over the sequenced defaults. As a
  side effect, building a factory that has associations still creates the
  associated records so their ids can be assigned to the parent.
  """
  @spec build(factory_name()) :: struct()
  @spec build(factory_name(), overrides()) :: struct()
  def build(factory_name, overrides \\ []) do
    {struct, _created} = build_with_assocs(factory_name, overrides)
    struct
  end

  @doc """
  Builds and validates a struct, then persists it on success.

  On success returns `{:ok, persisted_struct}` (via `MyApp.Repo.insert!/1`).
  On failure returns `{:error, {:missing_fields, fields}}` and rolls back any
  association records auto-created while building the invalid parent, leaving
  the repository unchanged.
  """
  @spec insert(factory_name()) :: {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
  @spec insert(factory_name(), overrides()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
  def insert(factory_name, overrides \\ []) do
    {struct, created} = build_with_assocs(factory_name, overrides)

    case missing_fields(factory_name, struct) do
      [] ->
        {:ok, MyApp.Repo.insert!(struct)}

      missing ->
        rollback(created)
        {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Like `insert/2`, but returns the persisted struct directly on success and
  raises `ArgumentError` on validation failure (after rolling back any
  auto-created associations).
  """
  @spec insert!(factory_name()) :: struct()
  @spec insert!(factory_name(), overrides()) :: struct()
  def insert!(factory_name, overrides \\ []) do
    case insert(factory_name, overrides) do
      {:ok, struct} ->
        struct

      {:error, {:missing_fields, missing}} ->
        raise ArgumentError,
              "cannot insert #{inspect(factory_name)}: missing required " <>
                "fields #{inspect(missing)}"
    end
  end

  @doc """
  Returns `true` if the struct built for `factory_name` passes validation.

  This never persists the parent, so any association records auto-created while
  building are always rolled back — a validity check leaves no stray rows.
  """
  @spec valid?(factory_name()) :: boolean()
  @spec valid?(factory_name(), overrides()) :: boolean()
  def valid?(factory_name, overrides \\ []) do
    {struct, created} = build_with_assocs(factory_name, overrides)
    missing = missing_fields(factory_name, struct)
    rollback(created)
    missing == []
  end

  @doc """
  Returns the next value for the sequence `name`.

  `formatter_fn` is called with `n`, a monotonically increasing integer
  starting at 1, with one independent counter per `name`. Values are unique
  across the whole test run even under concurrent access, backed by the named
  `Agent` started by `start/0`.
  """
  @spec sequence(atom(), (pos_integer() -> value)) :: value when value: var
  def sequence(name, formatter_fn) do
    n =
      Agent.get_and_update(@agent, fn state ->
        next = Map.get(state, name, 0) + 1
        {next, Map.put(state, name, next)}
      end)

    formatter_fn.(n)
  end

  # --- Internal helpers -----------------------------------------------------

  # Builds a struct and returns `{struct, created_assocs}` where
  # `created_assocs` is the list of persisted association records that should
  # be rolled back if the parent turns out to be invalid.
  @spec build_with_assocs(factory_name(), overrides()) :: {struct(), [struct()]}
  defp build_with_assocs(:user, overrides) do
    defaults = [
      name: sequence(:user_name, fn n -> "User #{n}" end),
      email: sequence(:user_email, fn n -> "user#{n}@example.com" end)
    ]

    {struct!(MyApp.User, Keyword.merge(defaults, overrides)), []}
  end

  defp build_with_assocs(:post, overrides) do
    {created, user_id} =
      case Keyword.fetch(overrides, :user_id) do
        {:ok, id} ->
          {[], id}

        :error ->
          user = MyApp.Repo.insert!(build(:user))
          {[user], user.id}
      end

    defaults = [
      title: sequence(:post_title, fn n -> "Post #{n}" end),
      body: sequence(:post_body, fn n -> "Body #{n}" end),
      user_id: user_id
    ]

    {struct!(MyApp.Post, Keyword.merge(defaults, overrides)), created}
  end

  # Returns the list of required fields whose value is nil on `struct`.
  @spec missing_fields(factory_name(), struct()) :: [atom()]
  defp missing_fields(factory_name, struct) do
    @required
    |> Map.fetch!(factory_name)
    |> Enum.filter(fn field -> is_nil(Map.get(struct, field)) end)
  end

  # Deletes previously auto-created association records.
  @spec rollback([struct()]) :: :ok
  defp rollback(created) do
    Enum.each(created, fn record -> MyApp.Repo.delete!(record) end)
  end
end