# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.StructFieldFilteringTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultProcessor

  defmodule User do
    use Ash.Resource,
      domain: AshTypescript.Test.Domain,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
      attribute :email, :string, public?: true
      attribute :secret, :string, public?: false
      attribute :internal_notes, :string, public?: false
    end

    calculations do
      calculate :self_struct, :struct, fn records, _ ->
        Enum.map(records, & &1)
      end do
        constraints instance_of: __MODULE__
        public? true
      end
    end

    actions do
      defaults [:read]

      action :search, {:array, Ash.Type.Struct} do
        constraints items: [instance_of: __MODULE__]

        argument :query, :string, allow_nil?: false

        run fn _input, _context ->
          # Return test records
          records = [
            struct(__MODULE__, %{
              id: Ash.UUID.generate(),
              name: "John Doe",
              email: "john@example.com",
              secret: "secret1",
              internal_notes: "internal1"
            })
          ]

          {:ok, records}
        end
      end
    end
  end

  describe "struct field filtering" do
    test "filters struct fields to only public attributes when no selection is specified" do
      # Create a struct with both public and private fields
      user_struct =
        struct(User, %{
          id: Ash.UUID.generate(),
          name: "Test User",
          email: "test@example.com",
          secret: "secret_value",
          internal_notes: "internal_notes"
        })

      # Process without field selection
      result = ResultProcessor.normalize_value_for_json(user_struct)

      # Should only include public fields
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :email)
      refute Map.has_key?(result, :secret)
      refute Map.has_key?(result, :internal_notes)
    end

    test "respects field selection when processing struct fields" do
      user_struct =
        struct(User, %{
          id: Ash.UUID.generate(),
          name: "Test User",
          email: "test@example.com",
          secret: "secret_value",
          internal_notes: "internal_notes"
        })

      # Process with specific field selection
      extraction_template = [:name]
      result = ResultProcessor.process(user_struct, extraction_template, User)

      # Should only include selected field
      assert Map.has_key?(result, :name)
      refute Map.has_key?(result, :id)
      refute Map.has_key?(result, :email)
      refute Map.has_key?(result, :secret)
    end

    test "handles nested struct fields by filtering to public attributes" do
      # Create a record with a struct field
      record_with_struct = %{
        id: Ash.UUID.generate(),
        name: "Main User",
        email: "main@example.com",
        self_struct:
          struct(User, %{
            id: Ash.UUID.generate(),
            name: "Nested User",
            email: "nested@example.com",
            secret: "nested_secret",
            internal_notes: "nested_notes"
          })
      }

      # Process with struct field included
      extraction_template = [:id, :name, :email, :self_struct]
      result = ResultProcessor.process(record_with_struct, extraction_template, User)

      # Main record fields
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :email)

      # Nested struct should only have public fields
      assert is_map(result[:self_struct])
      assert Map.has_key?(result[:self_struct], :id)
      assert Map.has_key?(result[:self_struct], :name)
      assert Map.has_key?(result[:self_struct], :email)
      refute Map.has_key?(result[:self_struct], :secret)
      refute Map.has_key?(result[:self_struct], :internal_notes)
    end

    test "supports field selection on nested struct fields" do
      record_with_struct = %{
        id: Ash.UUID.generate(),
        name: "Main User",
        self_struct:
          struct(User, %{
            id: Ash.UUID.generate(),
            name: "Nested User",
            email: "nested@example.com",
            secret: "nested_secret",
            internal_notes: "nested_notes"
          })
      }

      # Process with specific field selection on the struct field
      extraction_template = [:id, :name, {:self_struct, [:name]}]
      result = ResultProcessor.process(record_with_struct, extraction_template, User)

      # Main record fields
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :name)

      # Nested struct should only have the selected field
      assert is_map(result[:self_struct])
      assert Map.has_key?(result[:self_struct], :name)
      refute Map.has_key?(result[:self_struct], :id)
      refute Map.has_key?(result[:self_struct], :email)
      refute Map.has_key?(result[:self_struct], :secret)
    end

    test "handles arrays of structs by filtering each to public attributes" do
      # Simulate an action that returns array of structs
      action_result = [
        struct(User, %{
          id: Ash.UUID.generate(),
          name: "User 1",
          email: "user1@example.com",
          secret: "secret1",
          internal_notes: "notes1"
        }),
        struct(User, %{
          id: Ash.UUID.generate(),
          name: "User 2",
          email: "user2@example.com",
          secret: "secret2",
          internal_notes: "notes2"
        })
      ]

      # Process without field selection
      result = ResultProcessor.process(action_result, [], User)

      assert length(result) == 2

      Enum.each(result, fn user ->
        assert Map.has_key?(user, :id)
        assert Map.has_key?(user, :name)
        assert Map.has_key?(user, :email)
        refute Map.has_key?(user, :secret)
        refute Map.has_key?(user, :internal_notes)
      end)
    end

    test "handles arrays of structs with field selection" do
      action_result = [
        struct(User, %{
          id: Ash.UUID.generate(),
          name: "User 1",
          email: "user1@example.com",
          secret: "secret1",
          internal_notes: "notes1"
        })
      ]

      # Process with field selection
      extraction_template = [:name]
      result = ResultProcessor.process(action_result, extraction_template, User)

      assert length(result) == 1
      [user] = result

      assert Map.has_key?(user, :name)
      refute Map.has_key?(user, :id)
      refute Map.has_key?(user, :email)
      refute Map.has_key?(user, :secret)
    end
  end
end
