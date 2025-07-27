defmodule AshTypescript.Test.TodoTimestamp do
  use Ash.TypedStruct

  typed_struct do
    field(:created_by, :string, allow_nil?: false, description: "Test")
    field(:created_at, :utc_datetime, allow_nil?: false, description: "Test")
    field(:updated_by, :string, description: "Test")
    field(:updated_at, :utc_datetime, description: "Test")
  end
end
