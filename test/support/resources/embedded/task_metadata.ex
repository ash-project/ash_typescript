defmodule AshTypescript.Test.TaskMetadata do
  @moduledoc """
  Test embedded resource with field name mappings for Zod schema testing.

  This resource demonstrates field mappings in embedded resources:
  - `created_by?` -> `created_by` (removing question mark)
  - `is_public?` -> `is_public` (removing question mark)
  """

  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "TaskMetadata"
    field_names created_by?: :created_by, is_public?: :is_public
  end

  attributes do
    uuid_primary_key :id

    attribute :notes, :string do
      public? true
      allow_nil? true
    end

    attribute :created_by?, :string do
      public? true
      allow_nil? false
    end

    attribute :is_public?, :boolean do
      public? true
      allow_nil? false
      default false
    end

    attribute :priority_level, :integer do
      public? true
      allow_nil? true
      constraints min: 1, max: 5
    end
  end
end
