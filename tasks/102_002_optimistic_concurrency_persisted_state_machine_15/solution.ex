  @doc """
  Creates the `entity_transitions` table and its `entity_id` index.
  """
  def change do
    create table(:entity_transitions) do
      add(:entity_id, :string, null: false)
      add(:event, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:version, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(index(:entity_transitions, [:entity_id]))
  end