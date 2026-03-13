# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.GeneratorTest do
  use ExUnit.Case, async: true

  describe "generate/1" do
    test "generates spec for otp_app" do
      assert {:ok, %AshApiSpec{} = spec} = AshApiSpec.generate(otp_app: :ash_typescript)
      assert spec.version == "1.0.0"
      assert is_list(spec.resources)
      assert spec.resources != []
    end

    test "all resources have names and modules" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      for resource <- spec.resources do
        assert is_binary(resource.name)
        assert is_atom(resource.module)
        assert is_boolean(resource.embedded?)
        assert is_map(resource.fields)
        assert is_map(resource.relationships)
        assert is_map(resource.actions)
      end
    end

    test "includes Todo resource" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      todo = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.Todo))
      assert todo != nil
      assert todo.name == "Todo"

      # Should have fields
      assert Map.has_key?(todo.fields, :id)
      assert Map.has_key?(todo.fields, :title)
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
      assert Map.has_key?(todo.actions, :read)
    end

    test "with action filter, reachable resources have no actions" do
      {:ok, spec} =
        AshApiSpec.generate(
          otp_app: :ash_typescript,
          actions: [{AshTypescript.Test.Todo, :read}]
        )

      # User is reachable via Todo's belongs_to but was not explicitly listed
      user = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.User))
      assert user != nil
      assert user.actions == %{}
    end

    test "resources have properly resolved field types" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      todo = Enum.find(spec.resources, &(&1.module == AshTypescript.Test.Todo))
      assert todo.fields[:title].type.kind == :string
    end

    test "resources are sorted by module name" do
      {:ok, spec} = AshApiSpec.generate(otp_app: :ash_typescript)

      module_names = Enum.map(spec.resources, &Module.split(&1.module))
      assert module_names == Enum.sort(module_names)
    end
  end
end
