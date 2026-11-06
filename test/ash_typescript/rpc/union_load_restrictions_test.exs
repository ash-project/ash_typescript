# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Resources are defined at top level so Spark DSL fully compiles them before
# the inline domains reference them.

defmodule AshTypescript.Rpc.UnionLoadRestrictionsTest.Text do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

  typescript do
    type_name "UnionLoadsText"
  end

  attributes do
    attribute :body, :string, public?: true
  end

  calculations do
    calculate :display_body, :string, expr(body), public?: true
  end
end

defmodule AshTypescript.Rpc.UnionLoadRestrictionsTest.Post do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "UnionLoadsPost"
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :union do
      public? true

      constraints types: [
                    text: [
                      type: AshTypescript.Rpc.UnionLoadRestrictionsTest.Text,
                      tag: :kind,
                      tag_value: "text"
                    ],
                    note: [type: :string],
                    texts: [type: {:array, AshTypescript.Rpc.UnionLoadRestrictionsTest.Text}]
                  ],
                  storage: :type_and_value
    end

    attribute :blocks, {:array, :union} do
      public? true

      constraints items: [
                    types: [
                      text: [
                        type: AshTypescript.Rpc.UnionLoadRestrictionsTest.Text,
                        tag: :kind,
                        tag_value: "text"
                      ],
                      note: [type: :string]
                    ],
                    storage: :type_and_value
                  ]
    end
  end

  calculations do
    calculate :picked, :union, expr(nil) do
      public? true

      constraints types: [
                    text: [
                      type: AshTypescript.Rpc.UnionLoadRestrictionsTest.Text,
                      tag: :kind,
                      tag_value: "text"
                    ],
                    note: [type: :string]
                  ],
                  storage: :type_and_value

      argument :mode, :string, allow_nil?: true
    end

    calculate :related_texts, {:array, :struct}, expr(nil) do
      public? true
      constraints items: [instance_of: AshTypescript.Rpc.UnionLoadRestrictionsTest.Text]
      argument :limit, :integer, allow_nil?: true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.UnionLoadRestrictionsTest.CodegenDomain do
  @moduledoc false
  use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTypescript.Rpc.UnionLoadRestrictionsTest.Post do
      rpc_action :list_union_posts_deny_texts, :read,
        denied_loads: [
          content: [texts: [:display_body]],
          picked: [text: [:display_body]],
          related_texts: [:display_body]
        ]
    end
  end

  resources do
    resource AshTypescript.Rpc.UnionLoadRestrictionsTest.Post
  end
end

defmodule AshTypescript.Rpc.UnionLoadRestrictionsTest do
  # `allowed_loads` / `denied_loads` through union members: the level under a
  # union names its members (`content: [text: [:display_text]]`), checked when
  # the manifest compiles and enforced by ash_rpc's field selection.
  use ExUnit.Case, async: false
  import AshTypescript.Test.TestHelpers, only: [parse_selection: 2]

  @moduletag :ash_typescript

  for {name, option, loads, line} <- [
        {:accept_deny, :denied_loads, [content: [text: [:display_body]]], nil},
        {:accept_allow, :allowed_loads, [content: [text: [:display_body]]], nil},
        {:accept_bare_members, :denied_loads, [content: [:text, :note]], nil},
        {:accept_flat_union, :allowed_loads, [:content], nil},
        {:accept_array, :denied_loads, [blocks: [text: [:display_body]]], nil},
        {:unknown_member, :denied_loads, [content: [video: [:x]]],
         "  - content.video (no member :video in the union :content on " <>
           "AshTypescript.Rpc.UnionLoadRestrictionsTest.Post)"},
        {:under_scalar_member, :allowed_loads, [content: [note: [:x]]],
         "  - content.note (the member :note of the union :content on " <>
           "AshTypescript.Rpc.UnionLoadRestrictionsTest.Post has no fields to load under it)"},
        {:flat_member_field, :denied_loads, [content: [:display_body]],
         "  - content.display_body (no member :display_body in the union :content on " <>
           "AshTypescript.Rpc.UnionLoadRestrictionsTest.Post)"},
        {:unknown_member_field, :denied_loads, [blocks: [text: [:nope]]],
         "  - blocks.text.nope (no loadable public field :nope on " <>
           "AshTypescript.Rpc.UnionLoadRestrictionsTest.Text)"}
      ] do
    test "the verifier #{if line, do: "rejects", else: "accepts"} #{option}: #{inspect(loads)}" do
      domain = Module.concat(__MODULE__, Macro.camelize("#{unquote(name)}_domain"))

      {{:module, ^domain, _, _}, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          defmodule domain do
            use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

            typescript_rpc do
              resource AshTypescript.Rpc.UnionLoadRestrictionsTest.Post do
                rpc_action :list_union_posts, :read, [{unquote(option), unquote(loads)}]
              end
            end

            resources do
              resource AshTypescript.Rpc.UnionLoadRestrictionsTest.Post
            end
          end
        end)

      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:standard_error, fn ->
          AshTypescript.Manifest.verify_for_domains([domain])
        end)

      case unquote(line) do
        nil ->
          assert result == :ok

        line ->
          assert {:error, message} = result

          assert message =~
                   "RPC action list_union_posts: #{unquote(option)} contains invalid load paths:\n\n" <>
                     line <> "\n"
      end
    end
  end

  describe "the restricted schema" do
    test "a member holding an array of resources keeps the array" do
      schema_def = restricted_schema(:list_union_posts_deny_texts)

      assert schema_def =~
               "texts?: Array<ListUnionPostsDenyTextsSchemaContentTexts>; } | null;"

      assert schema_def =~
               "type ListUnionPostsDenyTextsSchemaContentTexts = " <>
                 "Omit<UnionLoadsTextResourceSchema, '__primitiveFields' | 'displayBody'>"
    end

    test "calculations with arguments keep them, arrays included" do
      schema_def = restricted_schema(:list_union_posts_deny_texts)

      assert schema_def =~
               ~s(  picked: { __type: "ComplexCalculation"; __returnType: { __type: "Union"; ) <>
                 ~s(__primitiveFields: "note"; text?: ListUnionPostsDenyTextsSchemaPickedText; ) <>
                 "note?: string; } | null; __args: { mode?: string | null }; };\n"

      assert schema_def =~
               ~s(  relatedTexts: { __type: "ComplexCalculation"; ) <>
                 "__returnType: Array<ListUnionPostsDenyTextsSchemaRelatedTexts> | null; " <>
                 "__args: { limit?: number | null }; };\n"
    end
  end

  describe "the runtime" do
    test "a denied member field is load_denied through the member" do
      assert {:error, {:load_denied, [[:content, :text, :display_text]]}} =
               parse_selection("list_todos_deny_union_member", [
                 "id",
                 %{"content" => [%{"text" => ["displayText"]}]}
               ])
    end

    test "other fields and members stay selectable under a denied member field" do
      assert {:ok, request} =
               parse_selection("list_todos_deny_union_member", [
                 "id",
                 %{"content" => [%{"text" => ["text", "isFormatted"]}, "note"]}
               ])

      assert {:content, [text: [:is_formatted]]} in request.load
    end

    test "the allowed member field is selectable" do
      assert {:ok, request} =
               parse_selection("list_todos_allow_union_member", [
                 "id",
                 %{"content" => [%{"text" => ["displayText"]}, "note"]}
               ])

      assert {:content, [text: [:display_text]]} in request.load
    end

    test "another field of the member is load_not_allowed" do
      assert {:error, {:load_not_allowed, [[:content, :text, :is_formatted]]}} =
               parse_selection("list_todos_allow_union_member", [
                 "id",
                 %{"content" => [%{"text" => ["isFormatted"]}]}
               ])
    end

    test "a field of another member is load_not_allowed" do
      assert {:error, {:load_not_allowed, [[:content, :checklist, :total_items]]}} =
               parse_selection("list_todos_allow_union_member", [
                 "id",
                 %{"content" => [%{"checklist" => ["title", "totalItems"]}]}
               ])
    end

    test "an array of unions is denied through the member" do
      assert {:error, {:load_denied, [[:blocks, :text, :display_text]]}} =
               parse_selection("list_todos_deny_block_member", [
                 "id",
                 %{"blocks" => [%{"text" => ["displayText"]}]}
               ])

      assert {:ok, _request} =
               parse_selection("list_todos_deny_block_member", [
                 "id",
                 %{"blocks" => [%{"text" => ["text"]}, "note"]}
               ])
    end

    test "run_action answers a denied member field with a load_denied error" do
      result =
        AshRpc.run_action(AshTypescript.RpcProfile, %Plug.Conn{}, %{
          "action" => "list_todos_deny_union_member",
          "fields" => ["id", %{"content" => [%{"text" => ["displayText"]}]}]
        })

      assert %{"success" => false, "errors" => [error | _]} = result
      assert error["type"] == "load_denied"
    end
  end

  defp restricted_schema(rpc_name) do
    manifest =
      AshTypescript.Test.InlineManifest.build!(
        domains: [AshTypescript.Rpc.UnionLoadRestrictionsTest.CodegenDomain],
        body: nil
      )

    {schema_def, _name} =
      AshTypescript.with_manifest(manifest, fn ->
        AshTypescript.Rpc.Codegen.TypeGenerators.RestrictedSchema.get_schema_and_reference(
          AshTypescript.Rpc.UnionLoadRestrictionsTest.Post,
          %{name: rpc_name},
          AshRpc.Manifest.resource_lookup(manifest)
        )
      end)

    schema_def
  end
end
