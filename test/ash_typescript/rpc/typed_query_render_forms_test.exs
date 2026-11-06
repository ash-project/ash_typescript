# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypedQueryRenderFormsTest do
  @moduledoc """
  Typed-query forms the test domain's typed queries don't use: a get action
  (one record, not an array), sort modifiers other than `-`, filter
  functions and operators whose value isn't the field's own type (`has`,
  `isNil`, `contains`), a selection into an array of embedded resources, a
  union selected by a map of members, and a calculation envelope with a key
  the runtime ignores. Filters written as lists and keyword lists render in the
  generated types' forms; filters and sorts the runtime rejects are reported by
  the verifier, and the forms the runtime takes but the generated types have
  no form for raise in codegen.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, InlineManifest}

  defmodule Domain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Test.Todo do
        typed_query :one_todo, :get_by_id do
          ts_fields_const_name "oneTodo"
          ts_result_type_name "OneTodoResult"
          fields [:id]
        end

        typed_query :render_forms, :read do
          ts_fields_const_name "renderForms"
          ts_result_type_name "RenderFormsResult"

          fields [
            :id,
            %{metadata_history: [:category]},
            %{content: %{text: [:text]}},
            %{self: %{args: %{prefix: "x"}, ignored: 1, fields: [:id]}},
            %{
              comments: %{
                sort: ["++authorName", "--rating", "+content"],
                fields: [:id]
              }
            }
          ]
        end
      end
    end

    resources do
      resource AshTypescript.Test.Todo
    end
  end

  defmodule FilterDomain do
    @moduledoc false
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    typescript_rpc do
      resource AshTypescript.Test.User do
        typed_query :filtered_todos, :read do
          ts_fields_const_name "filteredTodos"
          ts_result_type_name "FilteredTodosResult"

          fields [
            :id,
            %{
              todos: %{
                filter: %{
                  tags: %{has: "urgent"},
                  description: %{is_nil: true},
                  title: %{contains: "x"}
                },
                fields: [:id]
              }
            }
          ]
        end
      end
    end

    resources do
      resource AshTypescript.Test.User
    end
  end

  defp render(domain),
    do: CodegenTestHelper.typed_queries_section(InlineManifest.build!(domains: [domain]))

  setup_all do
    %{ts: render(Domain), filter_ts: render(FilterDomain)}
  end

  test "a typed query of a get action types one record", %{ts: ts} do
    assert ts =~
             ~s|export type OneTodoResult = InferResult<TodoResourceSchema, ["id"]>;|
  end

  test "sort modifiers are kept before the field's client name", %{ts: ts} do
    assert ts =~ ~s|sort: ["++authorName", "--rating", "+content"]|
  end

  test "a selection into an array of embedded resources", %{ts: ts} do
    assert ts =~ ~s|{ metadataHistory: ["category"] }|
  end

  test "a union selected with a map of members", %{ts: ts} do
    assert ts =~ ~s|{ content: { text: ["text"] } }|
  end

  test "a calculation envelope drops keys the runtime ignores", %{ts: ts} do
    assert ts =~ ~s|{ self: { args: { prefix: "x" }, fields: ["id"] } }|
  end

  test "has, isNil and contains filters", %{filter_ts: ts} do
    assert ts =~ ~s|tags: { has: "urgent" }|
    assert ts =~ ~s|description: { isNil: true }|
    assert ts =~ ~s|title: { contains: "x" }|
  end

  test "the filters and sorts above pass the verifier" do
    assert :ok = verify(Domain)
    assert :ok = verify(FilterDomain)
  end

  # Filters and sorts the runtime rejects when it builds the relationship's
  # query: `VerifyTypedQueryFields` reports them, so codegen never sees them.
  @rejected [
    {"a tuple value", quote(do: %{filter: %{author_name: %{is_nil: {:a, :b}}}}),
     "Invalid filter for relationship 'comments' at path []: Invalid filter value at " <>
       ~s|[:filter, :author_name, :is_nil]: {:invalid_filter_value, "A boolean value"}|},
    {"a map value of an untyped operator",
     quote(do: %{filter: %{author_name: %{is_nil: %{a: 1}}}}),
     "Invalid filter for relationship 'comments' at path []: Invalid filter value at " <>
       ~s|[:filter, :author_name, :is_nil]: {:invalid_filter_value, "A boolean value"}|},
    {"an unknown filter key", quote(do: %{filter: %{bogus: 1}}),
     "Invalid filter for relationship 'comments' at path []: " <>
       "No such field bogus for resource AshTypescript.Test.TodoComment"},
    {"a filter that isn't a map", quote(do: %{filter: [1]}),
     "Invalid filter for relationship 'comments' at path []: " <>
       "Invalid filter value at [:filter, 0]: :invalid_filter_statement"},
    {"a sort that isn't a list or a string", quote(do: %{sort: 5}),
     "Invalid sort for relationship 'comments' at path []: 5 is not a valid sort"},
    {"a sort entry that isn't a name", quote(do: %{sort: [5]}),
     "Invalid sort for relationship 'comments' at path []: 5 is not a valid sort"}
  ]

  for {{label, envelope, line}, index} <- Enum.with_index(@rejected) do
    test "#{label} is rejected by the verifier" do
      domain = Module.concat(__MODULE__, "Rejected#{unquote(index)}")
      envelope = unquote(Macro.escape(envelope))

      Module.create(
        domain,
        quote do
          use Ash.Domain,
            otp_app: :ash_typescript,
            extensions: [AshTypescript.Rpc],
            validate_config_inclusion?: false

          typescript_rpc do
            resource AshTypescript.Test.Todo do
              typed_query :rejected, :read do
                fields [:id, %{comments: Map.put(unquote(envelope), :fields, [:id])}]
              end
            end
          end

          resources do
            resource AshTypescript.Test.Todo
          end
        end,
        Macro.Env.location(__ENV__)
      )

      assert {:error, message} = verify(domain)

      assert message =~
               """
               Invalid field selection in typed query:
                 - Query: rejected
                 - Action: read
                 - Resource: AshTypescript.Test.Todo
                 - Error: #{unquote(line)}
               """
    end
  end

  # Filter forms the runtime reads as the generated types' forms: a list as
  # `and`, a keyword entry as a statement, keyword operators as a map.
  @rendered [
    {"a list filter", quote(do: %{filter: [%{author_name: %{eq: "x"}}, %{rating: %{gt: 1}}]}),
     ~s|filter: { and: [{ authorName: { eq: "x" } }, { rating: { gt: 1 } }] }|},
    {"a keyword list filter", quote(do: %{filter: [author_name: [eq: "x"], rating: 2]}),
     ~s|filter: { and: [{ authorName: { eq: "x" } }, { rating: { eq: 2 } }] }|},
    {"operators as a keyword list", quote(do: %{filter: %{author_name: [eq: "x", in: ["y"]]}}),
     ~s|filter: { authorName: { eq: "x", in: ["y"] } }|},
    {"a list under a connective and a relationship",
     quote(do: %{filter: %{or: [[rating: 1], %{user: [name: "x"]}]}}),
     ~s|filter: { or: [{ and: [{ rating: { eq: 1 } }] }, | <>
       ~s|{ user: { and: [{ name: { eq: "x" } }] } }] }|}
  ]

  for {{label, envelope, rendered}, index} <- Enum.with_index(@rendered) do
    test "#{label} renders as the generated types take it" do
      domain =
        define_domain(
          Module.concat(__MODULE__, "Rendered#{unquote(index)}"),
          unquote(Macro.escape(envelope))
        )

      assert :ok = verify(domain)
      assert render(domain) =~ "{ comments: { #{unquote(rendered)}, fields: [\"id\"] } }"
    end
  end

  # Filters the runtime takes but the generated types have no form for.
  @unrenderable [
    {"a tuple value for a field that isn't a tuple",
     quote(do: %{filter: %{author_name: %{eq: {:a, :b}}}}), "{:a, :b}"},
    {"a list value for an operator that takes one value",
     quote(do: %{filter: %{author_name: %{eq: ["a"]}}}), ~s|["a"]|},
    {"a boolean filter", quote(do: %{filter: true}), "true"}
  ]

  for {{label, envelope, part}, index} <- Enum.with_index(@unrenderable) do
    test "#{label} passes the verifier and raises in codegen" do
      domain =
        define_domain(
          Module.concat(__MODULE__, "Unrenderable#{unquote(index)}"),
          unquote(Macro.escape(envelope))
        )

      assert :ok = verify(domain)

      assert_raise ArgumentError,
                   "cannot render #{unquote(part)} in a typed query's fields: " <>
                     "the generated TypeScript types have no form for it",
                   fn -> render(domain) end
    end
  end

  defp define_domain(domain, envelope) do
    Module.create(
      domain,
      quote do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc],
          validate_config_inclusion?: false

        typescript_rpc do
          resource AshTypescript.Test.Todo do
            typed_query :envelope_filter, :read do
              fields [:id, %{comments: Map.put(unquote(envelope), :fields, [:id])}]
            end
          end
        end

        resources do
          resource AshTypescript.Test.Todo
        end
      end,
      Macro.Env.location(__ENV__)
    )

    domain
  end

  defp verify(domain) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains([domain])
      end)

    result
  end
end
