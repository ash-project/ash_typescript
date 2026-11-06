# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryClientNamesTest do
  @moduledoc """
  Typed queries that name fields by client names (strings), as the runtime
  accepts them. Client names hold under one output formatter only, so these
  typed queries live in an inline manifest rather than the test domain, which
  the formatter tests regenerate under other formatters.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, InlineManifest}

  @moduletag :ash_typescript

  defmodule Domain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Test.Todo do
        # Client names at every level: fields, typed map fields, union
        # members, calculation arguments, envelope and page keys, filter
        # fields and operators, and sorts
        typed_query :by_client_names, :read do
          ts_fields_const_name "byClientNames"
          ts_result_type_name "ByClientNamesResult"

          fields [
            "id",
            %{"user" => ["id", "isActive"]},
            %{"colorPalette" => ["primary"]},
            %{"content" => ["note", %{"text" => ["wordCount"]}]},
            %{"self" => %{"args" => %{"prefix" => "x"}, "fields" => ["id"]}},
            %{
              "comments" => %{
                "filter" => %{
                  "or" => [%{"authorName" => %{"eq" => "Ann"}}, %{"isHelpful" => true}]
                },
                "sort" => ["-authorName", "id"],
                "limit" => 1,
                "fields" => ["id", "authorName"]
              }
            },
            %{
              "offsetComments" => %{"page" => %{"limit" => 1, "offset" => 1}, "fields" => ["id"]}
            },
            %{"keysetComments" => %{"sort" => "authorName,-content", "fields" => ["content"]}},
            %{"unfilterableComments" => %{"sort" => "-content", "fields" => ["content"]}}
          ]
        end

        # The same selection by internal names; sort modifiers only exist on
        # client-name strings
        typed_query :by_internal_names, :read do
          ts_fields_const_name "byInternalNames"
          ts_result_type_name "ByInternalNamesResult"

          fields [
            :id,
            %{user: [:id, :is_active?]},
            %{color_palette: [:primary]},
            %{content: [:note, %{text: [:word_count]}]},
            %{self: %{args: %{prefix: "x"}, fields: [:id]}},
            %{
              comments: %{
                filter: %{or: [%{author_name: %{eq: "Ann"}}, %{is_helpful: true}]},
                sort: ["-authorName", :id],
                limit: 1,
                fields: [:id, :author_name]
              }
            },
            %{offset_comments: %{page: %{limit: 1, offset: 1}, fields: [:id]}},
            %{keyset_comments: %{sort: "authorName,-content", fields: [:content]}},
            %{unfilterable_comments: %{sort: "-content", fields: [:content]}}
          ]
        end
      end
    end

    resources do
      resource AshTypescript.Test.Todo
    end
  end

  # `test/ts/shouldPass/typedQueryEnvelopes.ts` type-checks this selection
  # against the generated `ListTodosFields` and `InferResult`.
  @selection ~s|["id", { user: ["id", "isActive"] }, { colorPalette: ["primary"] }, | <>
               ~s|{ content: ["note", { text: ["wordCount"] }] }, | <>
               ~s|{ self: { args: { prefix: "x" }, fields: ["id"] } }, | <>
               ~s|{ comments: { filter: { or: [{ authorName: { eq: "Ann" } }, | <>
               ~s|{ isHelpful: { eq: true } }] }, sort: ["-authorName", "id"], limit: 1, | <>
               ~s|fields: ["id", "authorName"] } }, | <>
               ~s|{ offsetComments: { page: { limit: 1, offset: 1 }, fields: ["id"] } }, | <>
               ~s|{ keysetComments: { sort: ["authorName", "-content"], fields: ["content"] } }, | <>
               ~s|{ unfilterableComments: { sort: "-content", fields: ["content"] } }]|

  setup_all do
    manifest = InlineManifest.build!(domains: [Domain])

    ts_output = CodegenTestHelper.typed_queries_section(manifest)

    %{manifest: manifest, ts_output: ts_output}
  end

  describe "codegen" do
    for {const, type} <- [
          {"byClientNames", "ByClientNamesResult"},
          {"byInternalNames", "ByInternalNamesResult"}
        ] do
      test "renders #{const} with the client names", %{ts_output: ts_output} do
        assert ts_output =~
                 "export const #{unquote(const)} = #{@selection};"

        assert ts_output =~
                 "export type #{unquote(type)} = " <>
                   "Array<InferResult<TodoResourceSchema, #{@selection}>>;"
      end
    end
  end

  describe "run_typed_query/4" do
    setup %{manifest: manifest} do
      user =
        AshTypescript.Test.User
        |> Ash.Changeset.for_create(:create, %{name: "Test User", email: "names@example.com"})
        |> Ash.create!()

      todo =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{title: "Names", user_id: user.id})
        |> Ash.create!()

      comments = AshTypescript.Test.TestHelpers.create_typed_query_comments!(todo, user)
      %{manifest: manifest, todo: todo, user: user, comments: comments}
    end

    for query <- [:by_client_names, :by_internal_names] do
      test "#{query} returns the selection", %{
        manifest: manifest,
        todo: todo,
        user: user,
        comments: comments
      } do
        assert %{"success" => true, "data" => data} =
                 AshTypescript.run_typed_query(unquote(query), %{}, %Plug.Conn{},
                   manifest: manifest
                 )

        row = Enum.find(data, &(&1["id"] == todo.id))
        {offset_page, row} = Map.pop(row, "offsetComments")

        assert row == %{
                 "id" => todo.id,
                 "user" => %{"id" => user.id, "isActive" => true},
                 "colorPalette" => nil,
                 "content" => nil,
                 "self" => %{"id" => todo.id},
                 "comments" => [%{"id" => comments["charlie"], "authorName" => "Bob"}],
                 "keysetComments" => [
                   %{"content" => "delta"},
                   %{"content" => "alpha"},
                   %{"content" => "charlie"},
                   %{"content" => "zulu"}
                 ],
                 "unfilterableComments" => [
                   %{"content" => "zulu"},
                   %{"content" => "delta"},
                   %{"content" => "charlie"},
                   %{"content" => "alpha"}
                 ]
               }

        # An offset page (`NestedOffsetPageResult` in the generated type)
        assert %{"results" => [%{"id" => _}], "hasMore" => true, "limit" => 1, "offset" => 1} =
                 offset_page
      end
    end
  end
end
