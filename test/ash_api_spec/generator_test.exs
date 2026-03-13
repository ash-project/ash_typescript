defmodule AshApiSpec.GeneratorTest do
  use ExUnit.Case, async: true

  describe "generate/1" do
    test "generates spec for otp_app" do
      assert {:ok, %AshApiSpec{} = spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      assert spec.version == "1.0.0"
      assert is_list(spec.resources)
      assert length(spec.resources) > 0
    end

    test "all resources have names and modules" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      for resource <- spec.resources do
        assert is_binary(resource.name)
        assert is_atom(resource.module)
        assert is_boolean(resource.embedded?)
        assert is_list(resource.fields)
        assert is_list(resource.relationships)
        assert is_list(resource.actions)
      end
    end

    test "includes Todo resource" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      todo = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.Todo))
      assert todo != nil
      assert todo.name == "Todo"

      # Should have fields
      field_names = Enum.map(todo.fields, & &1.name)
      assert :id in field_names
      assert :title in field_names
    end

    test "includes User resource" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      user = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.User))
      assert user != nil
    end

    test "with action filter narrows to specified actions" do
      {:ok, spec} =
        AshApiSpec.generate(
          otp_app: :ash_typescript,
          actions: [{AshTypescript.Test.Todo, :read}]
        )

      todo = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.Todo))
      assert todo != nil
      action_names = Enum.map(todo.actions, & &1.name)
      assert :read in action_names
    end

    test "resources have properly resolved field types" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      todo = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.Todo))
      title_field = Enum.find(todo.fields, &(&1.name == :title))

      assert title_field.type.kind == :string
    end

    test "resources are sorted by module name" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      module_names = Enum.map(spec.resources, &Module.split(&1.module))
      assert module_names == Enum.sort(module_names)
    end
  end
end
