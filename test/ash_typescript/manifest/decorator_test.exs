# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.DecoratorTest do
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.Custom

  setup_all do
    {:ok,
     api_spec: Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :manifest),
     resource_lookup: AshTypescript.resource_lookup()}
  end

  describe "resource decoration" do
    test "resources with AshTypescript.Resource extension carry .custom.ash_typescript",
         %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]
      assert %Manifest.Resource{custom: %{ash_typescript: _}} = user
      assert Custom.typescript_resource?(user)
    end

    test "field_name_mappings round-trips field_names DSL", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert Custom.field_name_mappings(user) == %{
               address_line_1: "addressLine1",
               is_active?: "isActive"
             }
    end

    test "reverse mapping is the inverse", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert Custom.original_field_name(user, "isActive") == :is_active?
      assert Custom.original_field_name(user, "addressLine1") == :address_line_1
      assert Custom.original_field_name(user, "doesNotExist") == nil
    end

    test "mapped_field_name returns explicit override", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert Custom.mapped_field_name(user, :is_active?) == "isActive"
      assert Custom.mapped_field_name(user, :name) == nil
    end

    test "argument_name_mappings round-trips argument_names DSL", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert Custom.mapped_argument_name(user, :read_with_invalid_arg, :is_active?) == "isActive"
      assert Custom.mapped_argument_name(user, :read_with_invalid_arg, :unmapped) == nil

      assert Custom.original_argument_name(user, :read_with_invalid_arg, "isActive") ==
               :is_active?
    end

    test "formatted_field_names contains entries for every public field × built-in formatter",
         %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      # field with explicit mapping wins over formatter
      assert Custom.formatted_field_name(user, :is_active?, :camel_case) == "isActive"
      assert Custom.formatted_field_name(user, :address_line_1, :camel_case) == "addressLine1"

      # field without mapping uses the formatter
      assert Custom.formatted_field_name(user, :name, :camel_case) == "name"

      # unknown formatter returns nil
      assert Custom.formatted_field_name(user, :name, :weird_format) == nil
    end

    test "resources without AshTypescript.Resource extension are not decorated",
         %{resource_lookup: lookup} do
      not_exposed = lookup[AshTypescript.Test.NotExposed]
      assert %Manifest.Resource{} = not_exposed
      refute Custom.typescript_resource?(not_exposed)
      assert Custom.field_name_mappings(not_exposed) == %{}
    end
  end

  describe "embedded resource decoration" do
    test "embedded resources nested in manifest.types carry .custom.ash_typescript",
         %{api_spec: spec} do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)
      task_metadata = type_lookup[AshTypescript.Test.TaskMetadata]

      assert %Manifest.Type{kind: :embedded_resource, resource: %Manifest.Resource{} = inner} =
               task_metadata

      assert Custom.typescript_resource?(inner)

      assert Custom.field_name_mappings(inner) == %{
               created_by?: "createdBy",
               is_public?: "isPublic"
             }
    end
  end

  describe "type decoration (NewTypes with typescript_field_names)" do
    test "Options NewType carries field_name_mappings on type.custom",
         %{api_spec: spec} do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)
      options = type_lookup[AshTypescript.Test.InputParsing.Options]

      assert %Manifest.Type{} = options
      assert Custom.type_field_name_mappings(options) == %{cache_enabled_1?: "cacheEnabled1"}

      assert Custom.reverse_type_field_name_mappings(options) == %{
               "cacheEnabled1" => :cache_enabled_1?
             }
    end
  end

  describe "entrypoint decoration" do
    test "rpc_action / domain / resource_config are mirrored to .custom.ash_typescript",
         %{api_spec: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e ->
          e.resource == AshTypescript.Test.Task and
            e.action.name == :read_with_invalid_metadata_names
        end)

      assert entrypoint
      assert Custom.rpc_action(entrypoint) != nil
      assert Custom.entrypoint_domain(entrypoint) != nil
      assert Custom.resource_config(entrypoint) != nil
    end

    test "metadata_field_mappings is derived from rpc_action.metadata_field_names",
         %{api_spec: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e ->
          e.resource == AshTypescript.Test.Task and
            e.action.name == :read_with_invalid_metadata_names
        end)

      assert Custom.metadata_field_mappings(entrypoint) == %{
               meta_1: "meta1",
               is_valid?: "isValid",
               field_2: "field2"
             }

      assert Custom.reverse_metadata_field_mappings(entrypoint) == %{
               "meta1" => :meta_1,
               "isValid" => :is_valid?,
               "field2" => :field_2
             }
    end

    test "entrypoints without metadata_field_names get empty mappings",
         %{api_spec: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e -> e.resource == AshTypescript.Test.User end)

      assert entrypoint
      assert Custom.metadata_field_mappings(entrypoint) == %{}
      assert Custom.reverse_metadata_field_mappings(entrypoint) == %{}
    end
  end

  describe "Custom accessors with nil / undecorated inputs" do
    test "all accessors handle nil gracefully" do
      assert Custom.ash_typescript(nil) == nil
      refute Custom.typescript_resource?(nil)
      assert Custom.field_name_mappings(nil) == %{}
      assert Custom.original_field_name(nil, "foo") == nil
      assert Custom.mapped_field_name(nil, :foo) == nil
      assert Custom.formatted_field_name(nil, :foo, :camel_case) == nil
      assert Custom.rpc_action(nil) == nil
      assert Custom.metadata_field_mappings(nil) == %{}
    end
  end

  describe "type_name decoration" do
    test "resource type_name derives from module name when no custom name", %{
      resource_lookup: lookup
    } do
      user = lookup[AshTypescript.Test.User]
      assert Custom.type_name(user) == "User"
    end

    test "resource type_name honors a custom typescript type_name", %{resource_lookup: lookup} do
      # Todo declares `type_name "Todo"` in its typescript DSL block.
      todo = lookup[AshTypescript.Test.Todo]
      assert Custom.type_name(todo) == "Todo"
    end

    test "type module type_name is present only when typescript_type_name/0 is exported", %{
      api_spec: spec
    } do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)
      color_palette = type_lookup[AshTypescript.Test.Todo.ColorPalette]

      if color_palette do
        assert Custom.type_name(color_palette) ==
                 AshTypescript.Test.Todo.ColorPalette.typescript_type_name()
      end
    end
  end

  describe "exposed_metadata_fields decoration" do
    test "show_metadata: nil exposes all action metadata names", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Task, :read_tasks_with_metadata_all)
      assert Custom.exposed_metadata_fields(e) == Enum.map(e.action.metadata, & &1.name)
    end

    test "show_metadata: false exposes none", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Task, :read_tasks_with_metadata_false)
      assert Custom.exposed_metadata_fields(e) == []
    end

    test "show_metadata: [] exposes none", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Task, :read_tasks_with_metadata_empty)
      assert Custom.exposed_metadata_fields(e) == []
    end

    test "explicit list is preserved", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Task, :read_tasks_with_metadata_two)
      assert Custom.exposed_metadata_fields(e) == [:some_string, :some_number]
    end
  end

  describe "load restrictions & filter/sort decoration" do
    test "allowed_loads → {:allow, verbatim list}", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_allow_only_user)
      assert Custom.load_restrictions(e) == {:allow, [:user]}
    end

    test "nested allowed_loads preserve the exact nested shape", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_allow_nested)
      assert Custom.load_restrictions(e) == {:allow, [:user, comments: [:todo]]}
    end

    test "denied_loads → {:deny, list}", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_deny_user)
      assert Custom.load_restrictions(e) == {:deny, [:user]}
    end

    test "neither → :none", %{api_spec: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_no_filter)
      assert Custom.load_restrictions(e) == :none
    end

    test "enable_filter?/enable_sort? default true, false when disabled", %{api_spec: spec} do
      default = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_allow_only_user)
      assert Custom.filtering_enabled?(default)
      assert Custom.sorting_enabled?(default)

      no_filter = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_no_filter)
      refute Custom.filtering_enabled?(no_filter)

      no_sort = entrypoint_for_rpc(spec, AshTypescript.Test.Todo, :list_todos_no_sort)
      refute Custom.sorting_enabled?(no_sort)
    end
  end

  defp entrypoint_for_rpc(spec, resource, rpc_name) do
    Enum.find(spec.entrypoints, fn e ->
      rpc = Custom.rpc_action(e)
      e.resource == resource and rpc != nil and rpc.name == rpc_name
    end)
  end
end
