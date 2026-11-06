# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.LoadPathsTest.Item do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "LoadPathsItem"
  end

  attributes do
    uuid_primary_key :id
    attribute :source_id, :uuid, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Manifest.LoadPathsTest.Source do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "LoadPathsSource"
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    has_many :items, AshTypescript.Manifest.LoadPathsTest.Item,
      destination_attribute: :source_id,
      public?: true
  end

  aggregates do
    count :items_count, :items, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Manifest.LoadPathsTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.LoadPaths
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema
  alias AshTypescript.Test.{Todo, TodoMetadata, User}

  @moduletag :ash_typescript

  setup_all do
    %{lookup: AshTypescript.resource_lookup(), types: AshTypescript.type_lookup()}
  end

  describe "step/4" do
    test "classifies the test resources' fields", %{lookup: lookup, types: types} do
      assert {:relationship, %{name: :user}, User} = LoadPaths.step(lookup, types, Todo, :user)

      assert {:embedded, %{name: :metadata}, TodoMetadata} =
               LoadPaths.step(lookup, types, Todo, :metadata)

      assert {:embedded, %{name: :metadata_history}, TodoMetadata} =
               LoadPaths.step(lookup, types, Todo, :metadata_history)

      assert {:resource_calculation, %{name: :self}, Todo} =
               LoadPaths.step(lookup, types, Todo, :self)

      assert {:leaf, %{name: :comment_count}} =
               LoadPaths.step(lookup, types, Todo, :comment_count)

      assert {:leaf, %{name: :is_overdue}} = LoadPaths.step(lookup, types, Todo, :is_overdue)

      assert {:union, %{name: :content}, %{kind: :union}} =
               LoadPaths.step(lookup, types, Todo, :content)

      assert {:union, %{name: :attachments}, %{kind: :union}} =
               LoadPaths.step(lookup, types, Todo, :attachments)

      assert {:union, %{name: :first_comment_author_info}, %{kind: :union}} =
               LoadPaths.step(lookup, types, Todo, :first_comment_author_info)

      assert {:embedded, %{name: :first_comment_metadata}, TodoMetadata} =
               LoadPaths.step(lookup, types, Todo, :first_comment_metadata)

      assert :invalid = LoadPaths.step(lookup, types, Todo, :title)
      assert :invalid = LoadPaths.step(lookup, types, Todo, :nope)
    end

    test "fields of an embedded resource", %{lookup: lookup, types: types} do
      assert {:leaf, %{name: :display_category}} =
               LoadPaths.step(lookup, types, TodoMetadata, :display_category)

      assert :invalid = LoadPaths.step(lookup, types, TodoMetadata, :category)
    end
  end

  describe "invalid_paths/4" do
    test "accepts relationship, embedded and resource-calculation paths", %{
      lookup: lookup,
      types: types
    } do
      assert [] =
               LoadPaths.invalid_paths(lookup, types, Todo, [
                 :user,
                 :comment_count,
                 comments: [:todo, :weighted_score],
                 metadata: [:display_category],
                 metadata_history: [:is_overdue],
                 self: [:user]
               ])
    end

    test "returns each invalid path with the resource it was looked up on", %{
      lookup: lookup,
      types: types
    } do
      assert [{[:nope], Todo, :unknown}] = LoadPaths.invalid_paths(lookup, types, Todo, [:nope])

      assert [{[:user, :nope], User, :unknown}] =
               LoadPaths.invalid_paths(lookup, types, Todo, user: [:nope])

      assert [{[:metadata, :category], TodoMetadata, :unknown}] =
               LoadPaths.invalid_paths(lookup, types, Todo, metadata: [:category])
    end

    test "nesting under a leaf is invalid", %{lookup: lookup, types: types} do
      assert [{[:comment_count], Todo, :leaf}] =
               LoadPaths.invalid_paths(lookup, types, Todo, comment_count: [:x])

      assert [{[:metadata, :display_category], TodoMetadata, :leaf}] =
               LoadPaths.invalid_paths(lookup, types, Todo, metadata: [display_category: [:x]])
    end

    test "entries that are not a name or a {name, nested} pair are skipped", %{
      lookup: lookup,
      types: types
    } do
      assert [] =
               LoadPaths.invalid_paths(lookup, types, Todo, ["user", {:user, :id}, {"user", []}])
    end

    test "under a union, entries that are not a member or a {member, nested} pair are skipped",
         %{lookup: lookup, types: types} do
      assert [] =
               LoadPaths.invalid_paths(lookup, types, Todo,
                 content: ["text", {:text, :display_text}, {"text", []}]
               )
    end

    test "a union takes member names at the next level", %{lookup: lookup, types: types} do
      assert [] =
               LoadPaths.invalid_paths(lookup, types, Todo, [
                 :content,
                 content: [:text, :note, text: [:display_text], checklist: [:total_items]],
                 attachments: [:url],
                 first_comment_author_info: [metadata: [:display_category]]
               ])
    end

    test "an unknown member, and a field where a member belongs, are unknown members",
         %{lookup: lookup, types: types} do
      assert [{[:content, :video], Todo, :unknown_member}] =
               LoadPaths.invalid_paths(lookup, types, Todo, content: [video: [:x]])

      assert [{[:content, :display_text], Todo, :unknown_member}] =
               LoadPaths.invalid_paths(lookup, types, Todo, content: [:display_text])
    end

    test "nesting under a scalar member is invalid", %{lookup: lookup, types: types} do
      assert [{[:content, :note], Todo, :scalar_member}] =
               LoadPaths.invalid_paths(lookup, types, Todo, content: [note: [:x]])
    end

    test "a field under a resource member is looked up on the member's resource",
         %{lookup: lookup, types: types} do
      assert [{[:content, :text, :nope], AshTypescript.Test.TodoContent.TextContent, :unknown}] =
               LoadPaths.invalid_paths(lookup, types, Todo, content: [text: [:nope]])
    end

    test "a union behind a NewType is resolved through the type lookup",
         %{lookup: lookup, types: types} do
      assert {:union, %{name: :item}, %{kind: :union}} =
               LoadPaths.step(lookup, types, AshTypescript.Test.Content, :item)

      assert [{[:item, :video], AshTypescript.Test.Content, :unknown_member}] =
               LoadPaths.invalid_paths(lookup, types, AshTypescript.Test.Content, item: [:video])
    end

    test "an aggregate holding an embedded resource is a step", %{lookup: lookup, types: types} do
      assert [] =
               LoadPaths.invalid_paths(lookup, types, Todo,
                 first_comment_metadata: [:display_category]
               )

      assert [{[:first_comment_metadata, :nope], TodoMetadata, :unknown}] =
               LoadPaths.invalid_paths(lookup, types, Todo, first_comment_metadata: [:nope])
    end
  end

  describe "the verifier accepts exactly the paths RestrictedSchema renders" do
    test "every restricted rpc_action of the test domain", %{lookup: lookup, types: types} do
      restricted =
        for {resource, rpc_action} <- rpc_actions(),
            restriction = rpc_action.allowed_loads || rpc_action.denied_loads,
            do: {resource, rpc_action, restriction}

      assert length(restricted) >= 12

      for {resource, rpc_action, restriction} <- restricted do
        assert LoadPaths.invalid_paths(lookup, types, resource, restriction) == [],
               "#{rpc_action.name}: #{inspect(restriction)}"

        assert {schema, name} =
                 RestrictedSchema.get_schema_and_reference(resource, rpc_action, lookup)

        assert name == FunctionNames.restricted_schema(rpc_action.name)
        assert schema =~ "type #{name} = "
      end
    end

    for {name, loads, path, message} <- [
          {:unknown_nested, [items: [:nope]], "items.nope",
           "no loadable public field :nope on AshTypescript.Manifest.LoadPathsTest.Item"},
          {:under_leaf, [items_count: [:x]], "items_count",
           ":items_count on AshTypescript.Manifest.LoadPathsTest.Source has no fields to load under it"},
          {:unknown, [:nope], "nope",
           "no loadable public field :nope on AshTypescript.Manifest.LoadPathsTest.Source"}
        ] do
      test "the verifier rejects #{inspect(loads)}" do
        domain = Module.concat(__MODULE__, "#{Macro.camelize(to_string(unquote(name)))}Domain")

        {{:module, ^domain, _, _}, _stderr} =
          ExUnit.CaptureIO.with_io(:standard_error, fn ->
            defmodule domain do
              use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

              typescript_rpc do
                resource AshTypescript.Manifest.LoadPathsTest.Source do
                  rpc_action :list_bad_loads, :read, denied_loads: unquote(loads)
                end
              end

              resources do
                resource AshTypescript.Manifest.LoadPathsTest.Source
                resource AshTypescript.Manifest.LoadPathsTest.Item
              end
            end
          end)

        {result, _stderr} =
          ExUnit.CaptureIO.with_io(:standard_error, fn ->
            AshTypescript.Manifest.verify_for_domains([domain])
          end)

        assert {:error, message} = result

        assert message =~
                 "RPC action list_bad_loads: denied_loads contains invalid load paths:\n\n" <>
                   "  - #{unquote(path)} (#{unquote(message)})\n"
      end
    end
  end

  defp rpc_actions do
    for domain <- [AshTypescript.Test.Domain, AshTypescript.Test.SecondDomain],
        Code.ensure_loaded?(domain),
        %{resource: resource, rpc_actions: rpc_actions} <-
          AshTypescript.Rpc.Info.typescript_rpc(domain),
        rpc_action <- rpc_actions,
        do: {resource, rpc_action}
  end
end
