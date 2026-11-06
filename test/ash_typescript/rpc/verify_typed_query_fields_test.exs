# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyTypedQueryFieldsTest do
  use ExUnit.Case, async: false

  describe "typed query field validation - invalid fields" do
    test "detects unknown field in typed query" do
      defmodule ResourceWithUnknownField do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnknownField"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :description, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithUnknownField do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithUnknownField do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :nonexistent_field]
            end
          end
        end

        resources do
          resource ResourceWithUnknownField
        end
      end

      result = silent_verify_for_domains([DomainWithUnknownField])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/nonexistent_field/i
    end

    test "detects private field in typed query" do
      defmodule ResourceWithPrivateField do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithPrivateField"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :internal_data, :string, public?: false
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithPrivateField do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithPrivateField do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :internal_data]
            end
          end
        end

        resources do
          resource ResourceWithPrivateField
        end
      end

      result = silent_verify_for_domains([DomainWithPrivateField])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/internal_data/i
    end

    test "detects duplicate fields in typed query" do
      defmodule ResourceWithDuplicateFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithDuplicateFields"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithDuplicateFields do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithDuplicateFields do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :title]
            end
          end
        end

        resources do
          resource ResourceWithDuplicateFields
        end
      end

      result = silent_verify_for_domains([DomainWithDuplicateFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Duplicate field/i
    end
  end

  describe "typed query field validation - relationships" do
    test "detects relationship without nested field selection" do
      defmodule ResourceWithRelationship do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithRelationship"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "Comment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule DomainWithRelationshipNoNested do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithRelationship do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :comments]
            end
          end
        end

        resources do
          resource ResourceWithRelationship
          resource ResourceWithRelationship.Comment
        end
      end

      result =
        silent_verify_for_domains([DomainWithRelationshipNoNested])

      assert {:error, error_message} = result
      assert error_message =~ ~r/requires nested field selection/i
    end

    test "detects unknown field in nested relationship" do
      defmodule ResourceWithNestedInvalid do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithNestedInvalid"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "NestedComment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule DomainWithNestedInvalid do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithNestedInvalid do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, %{comments: [:id, :nonexistent]}]
            end
          end
        end

        resources do
          resource ResourceWithNestedInvalid
          resource ResourceWithNestedInvalid.Comment
        end
      end

      result = silent_verify_for_domains([DomainWithNestedInvalid])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/nonexistent/i
    end
  end

  describe "typed query field validation - complex types" do
    test "detects calculation requiring arguments but not provided" do
      defmodule ResourceWithCalcArgs do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithCalcArgs"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        calculations do
          calculate :prefixed, :string, {__MODULE__.PrefixCalc, []} do
            public? true
            argument :prefix, :string, allow_nil?: false
          end
        end

        actions do
          defaults [:read]
        end

        defmodule PrefixCalc do
          use Ash.Resource.Calculation

          def calculate(records, _opts, %{arguments: %{prefix: prefix}}) do
            Enum.map(records, fn record ->
              "#{prefix}: #{record.title}"
            end)
          end
        end
      end

      defmodule DomainWithCalcNoArgs do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithCalcArgs do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :prefixed]
            end
          end
        end

        resources do
          resource ResourceWithCalcArgs
        end
      end

      result = silent_verify_for_domains([DomainWithCalcNoArgs])

      assert {:error, error_message} = result
      assert error_message =~ ~r/requires arguments/i
    end
  end

  describe "typed query field validation - valid cases" do
    test "accepts valid typed query with simple fields" do
      defmodule ValidResource do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ValidResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :description, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule ValidDomain do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ValidResource do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :description]
            end
          end
        end

        resources do
          resource ValidResource
        end
      end

      result = silent_verify_for_domains([ValidDomain])

      assert :ok = result
    end

    test "accepts valid typed query with nested relationships" do
      defmodule ValidResourceWithRel do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ValidResourceWithRel"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "ValidComment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule ValidDomainWithRel do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ValidResourceWithRel do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, %{comments: [:id, :content]}]
            end
          end
        end

        resources do
          resource ValidResourceWithRel
          resource ValidResourceWithRel.Comment
        end
      end

      result = silent_verify_for_domains([ValidDomainWithRel])

      assert :ok = result
    end
  end

  defmodule ErrorFormsDomain do
    use Ash.Domain,
      otp_app: :ash_typescript,
      extensions: [AshTypescript.Rpc],
      validate_config_inclusion?: false

    # One typed query per error `RequestedFieldsProcessor` reports, so each
    # line of the verifier's message is checked once.
    typescript_rpc do
      resource AshTypescript.Test.Todo do
        typed_query :unknown, :read, do: fields([:id, :nope])

        typed_query :typed_map_nested_empty, :read,
          do: fields([:id, %{statistics: [%{performance_metrics: []}]}])

        typed_query :relationship_bare, :read, do: fields([:id, :comments])
        typed_query :calc_without_args, :read, do: fields([:id, :self])
        typed_query :aggregate_nested, :read, do: fields([:id, %{comment_count: [:id]}])
        typed_query :attribute_nested, :read, do: fields([:id, %{title: [:id]}])
        typed_query :duplicate, :read, do: fields([:id, :id])
        typed_query :not_a_field, :read, do: fields([:id, 123])
        typed_query :relationship_atom, :read, do: fields([:id, %{comments: :id}])

        typed_query :scalar_calc_args, :read,
          do: fields([:id, %{is_overdue: %{args: %{}, fields: [:id]}}])

        typed_query :to_one_query_opts, :read,
          do: fields([:id, %{user: %{limit: 1, fields: [:id]}}])

        typed_query :attribute_query_opts, :read,
          do: fields([:id, %{title: %{limit: 1, fields: [:id]}}])

        typed_query :typed_map_query_opts, :read,
          do: fields([:id, %{statistics: [%{performance_metrics: %{limit: 1, fields: [:x]}}]}])

        typed_query :unknown_query_opts, :read,
          do: fields([:id, %{comments: %{limit: 1, bogus: 1, other: 2, fields: [:id]}}])

        typed_query :page_unknown_keys, :read,
          do: fields([:id, %{comments: %{page: %{bogus: 1}, fields: [:id]}}])

        typed_query :page_not_a_map, :read,
          do: fields([:id, %{comments: %{page: 5, fields: [:id]}}])

        typed_query :args_and_query_opts, :read,
          do: fields([:id, %{comments: %{args: %{}, limit: 1, fields: [:id]}}])

        typed_query :unpaginated_page, :read,
          do: fields([:id, %{unpaginated_comments: %{page: %{limit: 1}, fields: [:id]}}])

        typed_query :unfilterable_filter, :read,
          do:
            fields([
              :id,
              %{unfilterable_comments: %{filter: %{content: %{eq: "x"}}, fields: [:id]}}
            ])

        typed_query :unsortable_sort, :read,
          do: fields([:id, %{unsortable_comments: %{sort: [:content], fields: [:id]}}])

        typed_query :page_and_limit, :read,
          do: fields([:id, %{comments: %{page: %{limit: 1}, limit: 1, fields: [:id]}}])

        typed_query :negative_limit, :read,
          do: fields([:id, %{comments: %{limit: -1, fields: [:id]}}])

        typed_query :typed_map_args, :read,
          do:
            fields([
              :id,
              %{
                statistics: [
                  %{performance_metrics: %{args: %{}, fields: [:focus_time_seconds]}}
                ]
              }
            ])

        typed_query :primitive_selection, :read,
          do: fields([:id, %{statistics: [%{view_count: [:x]}]}])

        typed_query :nested_bad_sort, :read,
          do: fields([:id, %{user: [:id, %{todos: %{sort: 5, fields: [:id]}}]}])

        typed_query :bad_filter_in_calc, :read,
          do:
            fields([
              :id,
              %{
                self: %{
                  args: %{prefix: "x"},
                  fields: [:id, %{comments: %{filter: %{missing: 1}, fields: [:id]}}]
                }
              }
            ])

        # Inside a relationship's query, Ash holds nested relationships in its
        # `load` (copying their errors into the parent's) and calculations in
        # its `load_through`.
        typed_query :bad_filter_under_envelope, :read,
          do:
            fields([
              :id,
              %{
                comments: %{
                  fields: [
                    :id,
                    %{todo: [:id, %{comments: %{filter: %{absent: 1}, fields: [:id]}}]}
                  ]
                }
              }
            ])

        typed_query :bad_filter_under_calc, :read,
          do:
            fields([
              :id,
              %{
                comments: %{
                  fields: [
                    :id,
                    %{
                      todo: [
                        :id,
                        %{
                          self: %{
                            args: %{prefix: "x"},
                            fields: [:id, %{comments: %{filter: %{bogus: 1}, fields: [:id]}}]
                          }
                        }
                      ]
                    }
                  ]
                }
              }
            ])

        typed_query :integer_key, :read, do: fields([:id, %{1 => [:id]}])
      end
    end

    resources do
      resource AshTypescript.Test.Todo
    end
  end

  describe "typed query field validation - actions VerifyRpc reports" do
    defmodule ResourceWithPrivateRead do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "ResourceWithPrivateRead"
      end

      attributes do
        uuid_primary_key :id
      end

      actions do
        defaults [:read]

        read :hidden do
          public? false
        end
      end
    end

    defmodule DomainWithMissingAction do
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc],
        validate_config_inclusion?: false

      typescript_rpc do
        resource ResourceWithPrivateRead do
          typed_query :missing_action, :nope, do: fields([:id, :unknown])
        end
      end

      resources do
        resource ResourceWithPrivateRead
      end
    end

    defmodule DomainWithPrivateAction do
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc],
        validate_config_inclusion?: false

      typescript_rpc do
        resource ResourceWithPrivateRead do
          typed_query :private_action, :hidden, do: fields([:id, :unknown])
        end
      end

      resources do
        resource ResourceWithPrivateRead
      end
    end

    # VerifyRpc reports these; the field check skips them rather than also
    # reporting `:unknown` against the same root cause.
    test "a missing action is left to VerifyRpc" do
      assert {:error, message} = silent_verify_for_domains([DomainWithMissingAction])

      assert message =~
               "Typed query missing_action references action nope, which does not exist " <>
                 "on resource #{inspect(ResourceWithPrivateRead)}"

      refute message =~ "Invalid field selections found in typed queries."
    end

    test "a private action is left to VerifyRpc" do
      assert {:error, message} = silent_verify_for_domains([DomainWithPrivateAction])

      assert message =~
               "Typed query private_action references action hidden on " <>
                 "#{inspect(ResourceWithPrivateRead)}, which is not `public?`."

      refute message =~ "Invalid field selections found in typed queries."
    end
  end

  describe "typed query field validation - error lines" do
    setup do
      {:error, message} = silent_verify_for_domains([ErrorFormsDomain])
      {:ok, message: message}
    end

    for {query, error} <- [
          unknown: "Unknown field 'nope' at path []",
          typed_map_nested_empty:
            "Field at path [:statistics, :performance_metrics] is of type " <>
              "'field_constrained_type' and requires nested field selection",
          relationship_bare:
            "Field 'comments' at path [] is of type 'relationship' and requires nested field selection",
          calc_without_args: "Calculation 'self' at path [] requires arguments",
          aggregate_nested:
            "Invalid field selection for 'comment_count' at path [] (type: aggregate)",
          attribute_nested: "Field 'title' at path [] does not support nested field selection",
          duplicate: "Duplicate field 'id' at path []",
          not_a_field: "Invalid field type for 123 at path []",
          relationship_atom:
            "Unsupported field combination for relationship 'comments' with nested fields :id at path []",
          scalar_calc_args: "Invalid calculation arguments for 'is_overdue' at path []",
          to_one_query_opts:
            "Relationship 'user' at path [] is to-one and does not accept query options",
          attribute_query_opts:
            "Field 'title' at path [] is of kind 'attribute' and does not accept query options",
          typed_map_query_opts:
            "Field 'performance_metrics' at path [:statistics] is of kind 'typed field' " <>
              "and does not accept query options",
          unknown_query_opts:
            "Unknown query option keys for relationship 'comments' at path []: bogus, other",
          page_unknown_keys:
            "Invalid page for relationship 'comments' at path []: unknown keys bogus",
          page_not_a_map: "Invalid page for relationship 'comments' at path []: not a map",
          args_and_query_opts:
            "Relationship 'comments' at path [] combines args with query options; " <>
              "they are mutually exclusive",
          unpaginated_page:
            "Relationship 'unpaginated_comments' at path [] is not paginated and does not accept page",
          unfilterable_filter:
            "Relationship 'unfilterable_comments' at path [] does not support filter",
          unsortable_sort: "Relationship 'unsortable_comments' at path [] does not support sort",
          page_and_limit:
            "Relationship 'comments' at path [] combines page with limit/offset; use one or the other",
          negative_limit:
            "Query option 'limit' of relationship 'comments' at path [] must be a non-negative integer",
          typed_map_args:
            "Invalid field format %{performance_metrics: %{args: %{}, fields: [:focus_time_seconds]}} " <>
              "at path [:statistics]",
          primitive_selection:
            "Field at path [:statistics, :view_count] is of type 'Integer' and does not take " <>
              "a field selection (got [:x])",
          nested_bad_sort:
            "Invalid sort for relationship 'todos' at path [:user]: 5 is not a valid sort",
          bad_filter_in_calc:
            "Invalid filter for relationship 'comments' at path [:self]: " <>
              "No such field missing for resource AshTypescript.Test.TodoComment",
          bad_filter_under_envelope:
            "Invalid filter for relationship 'comments' at path [:comments, :todo]: " <>
              "No such field absent for resource AshTypescript.Test.TodoComment",
          bad_filter_under_calc:
            "Invalid filter for relationship 'comments' at path [:comments, :todo, :self]: " <>
              "No such field bogus for resource AshTypescript.Test.TodoComment"
        ] do
      test "reports #{query}", %{message: message} do
        assert message =~
                 """
                 Invalid field selection in typed query:
                   - Query: #{unquote(query)}
                   - Action: read
                   - Resource: AshTypescript.Test.Todo
                   - Error: #{unquote(error)}
                 """
      end
    end

    test "reports a nested query's error once, at the relationship it is on",
         %{message: message} do
      assert length(String.split(message, "No such field absent")) == 2
      assert length(String.split(message, "No such field bogus")) == 2
    end

    test "reports a selection the processor can't parse", %{message: message} do
      assert message =~
               """
               Failed to parse field names in typed query:
                 - Query: integer_key
                 - Action: read
                 - Error: no function clause matching in \
               AshRpc.FieldProcessing.FieldSelector.resolve_resource_field_name/3
               """
    end
  end

  describe "typed query field validation - errors the verifier has no line for" do
    alias AshTypescript.Manifest.Verifiers.VerifyTypedQueryFields

    test "an error shape the runtime adds later is reported as it came" do
      assert VerifyTypedQueryFields.format_field_error({:some_new_error, :comments, [:user]}) ==
               "Unexpected field selection error: {:some_new_error, :comments, [:user]}"
    end

    test "a page reason the runtime adds later is reported as it came" do
      assert VerifyTypedQueryFields.format_field_error(
               {:invalid_nested_page, :comments, {:some_new_reason, 1}, []}
             ) ==
               "Invalid page for relationship 'comments' at path []: {:some_new_reason, 1}"
    end

    test "a relationship query error from neither the filter nor the sort" do
      error = Ash.Error.Query.InvalidQuery.exception(message: "is broken")

      assert VerifyTypedQueryFields.format_field_error(
               {:invalid_relationship_query, :comments, error, [:user]}
             ) ==
               "Invalid query for relationship 'comments' at path [:user]: " <>
                 Exception.message(error)
    end

    test "a selection under a primitive without a type name names its kind, or none" do
      assert VerifyTypedQueryFields.format_field_error(
               {:invalid_field_selection, :primitive_type,
                %Ash.Info.Manifest.Type{kind: :integer}, [:x], []}
             ) ==
               "Field at path [] is of type 'integer' and does not take a field selection (got [:x])"

      assert VerifyTypedQueryFields.format_field_error(
               {:invalid_field_selection, :primitive_type, nil, [:x], []}
             ) ==
               "Field at path [] is of type 'unknown' and does not take a field selection (got [:x])"
    end
  end

  # Compiling the throwaway manifest module makes Elixir's parallel checker echo
  # raised DslErrors (and RPC config IO.warn output) to stderr, so silence it.
  defp silent_verify_for_domains(domains) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains(domains)
      end)

    result
  end
end
