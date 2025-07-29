defmodule AshTypescript.Rpc.DebugTypedStructTest do
  use ExUnit.Case

  test "debug TypedStruct field resolution" do
    # Test getting fields from TodoStatistics
    fields = AshTypescript.Codegen.get_typed_struct_fields(AshTypescript.Test.TodoStatistics)
    IO.inspect(fields, label: "TodoStatistics fields")

    # Test is_typed_struct? function
    fake_attr = %{type: AshTypescript.Test.TodoStatistics, constraints: [instance_of: AshTypescript.Test.TodoStatistics]}
    is_typed = AshTypescript.Rpc.RequestedFieldsProcessor.is_typed_struct?(fake_attr)
    IO.inspect(is_typed, label: "is_typed_struct?")

    # Test field processing directly
    field_specs_as_constraints = Enum.into(fields, [], fn field -> {field.name, [type: field.type]} end)
    IO.inspect(field_specs_as_constraints, label: "field_specs_as_constraints")

    # Test the actual field processing
    requested_fields = [:view_count, :edit_count]
    try do
      {_field_names, template_items} = AshTypescript.Rpc.RequestedFieldsProcessor.process_typed_struct_fields(requested_fields, field_specs_as_constraints, [])
      IO.inspect(template_items, label: "template_items")
    rescue
      error ->
        IO.inspect(error, label: "error in process_typed_struct_fields")
    end
  end
end