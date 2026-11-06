# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.DecoratorTest do
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions

  setup_all do
    {:ok,
     manifest: Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :manifest),
     resource_lookup: AshTypescript.resource_lookup()}
  end

  describe "resource decoration" do
    test "resources with AshTypescript.Resource extension carry .custom.ash_typescript",
         %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]
      assert %Manifest.Resource{custom: %{ash_typescript: _}} = user
      assert AshRpc.Manifest.Custom.exposed?(user)
    end

    test "field_name_mappings round-trips field_names DSL", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert AshRpc.Manifest.Custom.field_name_overrides(user) == %{
               address_line_1: "addressLine1",
               is_active?: "isActive"
             }
    end

    test "reverse mapping is the inverse", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert AshRpc.Manifest.Custom.original_field_name(user, "isActive") == :is_active?
      assert AshRpc.Manifest.Custom.original_field_name(user, "addressLine1") == :address_line_1
      assert AshRpc.Manifest.Custom.original_field_name(user, "doesNotExist") == nil
    end

    test "mapped_field_name returns explicit override", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert AshRpc.Manifest.Custom.field_name_override(user, :is_active?) == "isActive"
      assert AshRpc.Manifest.Custom.field_name_override(user, :name) == nil
    end

    test "argument_name_mappings round-trips argument_names DSL", %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      assert AshRpc.Manifest.Custom.argument_name_override(
               user,
               :read_with_invalid_arg,
               :is_active?
             ) == "isActive"

      assert AshRpc.Manifest.Custom.argument_name_override(
               user,
               :read_with_invalid_arg,
               :unmapped
             ) == nil

      assert AshRpc.Manifest.Custom.original_argument_name(
               user,
               :read_with_invalid_arg,
               "isActive"
             ) ==
               :is_active?
    end

    test "custom.ash_rpc field_names cover every public field for the configured formatter",
         %{resource_lookup: lookup} do
      user = lookup[AshTypescript.Test.User]

      # field with explicit mapping wins over formatter
      assert AshRpc.Manifest.Custom.field_names(user)[:is_active?] == "isActive"
      assert AshRpc.Manifest.Custom.field_names(user)[:address_line_1] == "addressLine1"

      # field without mapping uses the formatter
      assert AshRpc.Manifest.Custom.field_names(user)[:name] == "name"
    end

    test "resources without AshTypescript.Resource extension are not decorated",
         %{resource_lookup: lookup} do
      not_exposed = lookup[AshTypescript.Test.NotExposed]
      assert %Manifest.Resource{} = not_exposed
      refute AshRpc.Manifest.Custom.exposed?(not_exposed)
      assert AshRpc.Manifest.Custom.field_name_overrides(not_exposed) == %{}
    end
  end

  describe "embedded resource decoration" do
    test "embedded resources nested in manifest.types carry .custom.ash_typescript",
         %{manifest: spec} do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)
      task_metadata = type_lookup[AshTypescript.Test.TaskMetadata]

      assert %Manifest.Type{kind: :embedded_resource, resource: %Manifest.Resource{} = inner} =
               task_metadata

      assert AshRpc.Manifest.Custom.exposed?(inner)

      assert AshRpc.Manifest.Custom.field_name_overrides(inner) == %{
               created_by?: "createdBy",
               is_public?: "isPublic"
             }
    end
  end

  describe "type decoration (NewTypes with typescript_field_names)" do
    test "Options NewType carries field_name_mappings on type.custom",
         %{manifest: spec} do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)
      options = type_lookup[AshTypescript.Test.InputParsing.Options]

      assert %Manifest.Type{} = options

      assert AshRpc.Manifest.Custom.type_field_name_overrides(options) == %{
               cache_enabled_1?: "cacheEnabled1"
             }

      {_forward, reverse} = AshRpc.Manifest.Custom.type_field_name_overrides_pair(options)
      assert reverse == %{"cacheEnabled1" => :cache_enabled_1?}
    end
  end

  describe "entrypoint decoration" do
    test "rpc_action / domain are mirrored to .custom.ash_typescript",
         %{manifest: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e ->
          e.resource == AshTypescript.Test.Task and
            e.action.name == :read_with_invalid_metadata_names
        end)

      assert entrypoint
      assert Custom.rpc_action(entrypoint) != nil
      assert Custom.entrypoint_domain(entrypoint) != nil
    end

    test "the wire entrypoint's metadata_field_names come from rpc_action.metadata_field_names",
         %{manifest: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e ->
          e.resource == AshTypescript.Test.Task and
            e.action.name == :read_with_invalid_metadata_names
        end)

      assert wire(entrypoint).metadata_field_names == %{
               meta_1: "meta1",
               is_valid?: "isValid",
               field_2: "field2"
             }
    end

    test "entrypoints without metadata_field_names get empty mappings",
         %{manifest: spec} do
      entrypoint =
        Enum.find(spec.entrypoints, fn e ->
          e.resource == AshTypescript.Test.User and Custom.rpc_action(e) != nil
        end)

      assert entrypoint
      assert wire(entrypoint).metadata_field_names == %{}
    end
  end

  describe "Custom accessors with nil / undecorated inputs" do
    test "all accessors handle nil gracefully" do
      refute AshRpc.Manifest.Custom.exposed?(nil)
      assert AshRpc.Manifest.Custom.field_name_overrides(nil) == %{}
      assert AshRpc.Manifest.Custom.original_field_name(nil, "foo") == nil
      assert AshRpc.Manifest.Custom.field_name_override(nil, :foo) == nil
      assert Custom.rpc_action(nil) == nil
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

    test "type module type_name is present only when typescript_type/0 is exported", %{
      manifest: spec
    } do
      type_lookup = Ash.Info.Manifest.type_lookup(spec)

      # ColorPalette declares fields (a custom-type definition) and no
      # typescript_type/0; Percentage is a NewType that exports one.
      color_palette = type_lookup[AshTypescript.Test.Todo.ColorPalette]
      assert AshRpc.Manifest.Custom.custom_type?(color_palette)
      assert Custom.type_name(color_palette) == nil
    end
  end

  describe "type_name of declared custom types" do
    defmodule NamedFields do
      @moduledoc false
      # A declared custom type whose fields have TypeScript names.
      use Ash.Type

      def typescript_fields, do: [is_on?: [type: :boolean]]
      def typescript_field_names, do: [is_on?: "isOn"]

      @impl true
      def storage_type(_), do: :map
      @impl true
      def cast_input(value, _), do: {:ok, value}
      @impl true
      def cast_stored(value, _), do: {:ok, value}
      @impl true
      def dump_to_native(value, _), do: {:ok, value}
    end

    defmodule NamedFieldsMap do
      @moduledoc false
      # A NewType over :map with field names: still gets a type_name.
      use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [is_on?: [type: :boolean]]]

      def typescript_field_names, do: [is_on?: "isOn"]
    end

    defmodule NamedFieldsHolder do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "NamedFieldsHolder"
      end

      attributes do
        uuid_primary_key :id
      end

      actions do
        action :get_named, NamedFields do
          run fn _input, _context -> {:ok, %{is_on?: true}} end
        end

        action :get_named_map, NamedFieldsMap do
          run fn _input, _context -> {:ok, %{is_on?: true}} end
        end
      end
    end

    defmodule NamedFieldsDomain do
      @moduledoc false
      use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource NamedFieldsHolder do
          rpc_action :get_named, :get_named
          rpc_action :get_named_map, :get_named_map
        end
      end

      resources do
        resource NamedFieldsHolder
      end
    end

    test "a declared custom type gets names but no type_name, a NewType with field names gets a type_name" do
      type_lookup =
        [domains: [NamedFieldsDomain]]
        |> AshTypescript.Test.InlineManifest.build!()
        |> Ash.Info.Manifest.type_lookup()

      declared = type_lookup[NamedFields]
      assert AshRpc.Manifest.Custom.custom_type?(declared)
      assert AshRpc.Manifest.Custom.type_field_names(declared) == %{is_on?: "isOn"}

      assert declared.custom.ash_typescript == %{
               type_alias_names: %{
                 typescript: "AshTypescriptManifestDecoratorTestNamedFields",
                 zod: :derive,
                 valibot: :derive
               }
             }

      named_map = type_lookup[NamedFieldsMap]
      refute AshRpc.Manifest.Custom.custom_type?(named_map)
      assert Map.has_key?(named_map.custom, :ash_typescript)
    end
  end

  describe "entrypoint options" do
    @entrypoint_option_keys [
      :exposed_metadata_fields,
      :load_restrictions,
      :filtering_enabled?,
      :sorting_enabled?,
      :metadata_field_mappings,
      :reverse_metadata_field_mappings
    ]

    test "the decorator no longer stores entrypoint options", %{manifest: spec} do
      decorated =
        for e <- spec.entrypoints, ts = e.custom[:ash_typescript], ts[:rpc_action], do: ts

      assert decorated != []

      for ts <- decorated,
          do: assert(Map.take(ts, @entrypoint_option_keys) == %{}, inspect(ts.rpc_action.name))
    end
  end

  describe "exposed metadata fields on the wire entrypoint" do
    test "show_metadata: nil exposes all action metadata names", %{manifest: spec} do
      e = entrypoint_for_rpc(spec, AshTypescript.Test.Task, :read_tasks_with_metadata_all)

      assert EntrypointOptions.exposed_metadata_fields(wire(e)) ==
               Enum.map(e.action.metadata, & &1.name)
    end

    test "show_metadata: false exposes none" do
      assert EntrypointOptions.exposed_metadata_fields(wire(:read_tasks_with_metadata_false)) ==
               []
    end

    test "show_metadata: [] exposes none" do
      assert EntrypointOptions.exposed_metadata_fields(wire(:read_tasks_with_metadata_empty)) ==
               []
    end

    test "explicit list is preserved" do
      assert EntrypointOptions.exposed_metadata_fields(wire(:read_tasks_with_metadata_two)) ==
               [:some_string, :some_number]
    end
  end

  describe "load restrictions & filter/sort on the wire entrypoint" do
    test "allowed_loads → {:allow, verbatim list}" do
      assert EntrypointOptions.load_restrictions(wire(:list_todos_allow_only_user)) ==
               {:allow, [:user]}
    end

    test "nested allowed_loads preserve the exact nested shape" do
      assert EntrypointOptions.load_restrictions(wire(:list_todos_allow_nested)) ==
               {:allow, [:user, comments: [:todo]]}
    end

    test "denied_loads → {:deny, list}" do
      assert EntrypointOptions.load_restrictions(wire(:list_todos_deny_user)) == {:deny, [:user]}
    end

    test "neither → :none" do
      assert EntrypointOptions.load_restrictions(wire(:list_todos_no_filter)) == :none
    end

    test "enable_filter?/enable_sort? default true, false when disabled" do
      default = wire(:list_todos_allow_only_user)
      assert EntrypointOptions.filter_enabled?(default)
      assert EntrypointOptions.sort_enabled?(default)

      refute EntrypointOptions.filter_enabled?(wire(:list_todos_no_filter))
      refute EntrypointOptions.sort_enabled?(wire(:list_todos_no_sort))
    end
  end

  defp wire(%Manifest.Entrypoint{} = e), do: wire(Custom.rpc_action(e).name)
  defp wire(rpc_name), do: EntrypointOptions.entrypoint!(rpc_name)

  defp entrypoint_for_rpc(spec, resource, rpc_name) do
    Enum.find(spec.entrypoints, fn e ->
      rpc = Custom.rpc_action(e)
      e.resource == resource and rpc != nil and rpc.name == rpc_name
    end)
  end
end
