# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedQueryOptsTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.RequestedFieldsProcessor

  # Envelope maps may keep string keys after atomization (the FieldSelector
  # handles both); fetch tolerantly.
  defp fetch(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  describe "atomizer envelope passthrough" do
    test "page/filter/sort values pass through untouched; fields list is processed" do
      input = [
        "id",
        %{
          "comments" => %{
            "page" => %{"limit" => 3, "count" => true},
            "filter" => %{"rating" => %{"greaterThan" => 2}},
            "sort" => "-insertedAt",
            "limit" => 5,
            "offset" => 2,
            "fields" => ["id", "content"]
          }
        }
      ]

      [_, envelope_map] =
        RequestedFieldsProcessor.atomize_requested_fields(input, AshTypescript.Test.Todo)

      [{_comments_key, envelope}] = Map.to_list(envelope_map)

      # Option values must be byte-identical to what the client sent.
      assert fetch(envelope, :page) == %{"limit" => 3, "count" => true}
      assert fetch(envelope, :filter) == %{"rating" => %{"greaterThan" => 2}}
      assert fetch(envelope, :sort) == "-insertedAt"
      assert fetch(envelope, :limit) == 5
      assert fetch(envelope, :offset) == 2
      # The fields list is still present (as sent — resolution happens later).
      assert fetch(envelope, :fields) == ["id", "content"]
    end

    test "option-value keys colliding with field_names mappings are not mangled" do
      # User maps "isActive" -> :is_active?; a filter key spelled the same way
      # must still pass through byte-identical.
      input = [
        %{
          "todos" => %{
            "filter" => %{"isActive" => %{"eq" => true}},
            "page" => %{"isActive" => true},
            "fields" => ["id"]
          }
        }
      ]

      [envelope_map] =
        RequestedFieldsProcessor.atomize_requested_fields(input, AshTypescript.Test.User)

      [{_todos_key, envelope}] = Map.to_list(envelope_map)

      assert fetch(envelope, :filter) == %{"isActive" => %{"eq" => true}}
      assert fetch(envelope, :page) == %{"isActive" => true}
    end
  end

  defp process_fields(action, raw_fields, opts \\ []) do
    fields =
      RequestedFieldsProcessor.atomize_requested_fields(raw_fields, AshTypescript.Test.Todo)

    RequestedFieldsProcessor.process(AshTypescript.Test.Todo, action, fields, nil, opts)
  end

  describe "envelope classification and query build" do
    test "full envelope builds a nested Ash.Query load with formatted options" do
      raw = [
        "id",
        %{
          "comments" => %{
            "page" => %{"limit" => 3, "count" => true},
            "filter" => %{"rating" => %{"greaterThan" => 2}},
            "sort" => "-rating",
            "fields" => ["id", "content"]
          }
        }
      ]

      assert {:ok, {select, load, template}} = process_fields(:read, raw)

      assert select == [:id]
      assert [{:comments, %Ash.Query{} = query}] = load
      assert query.resource == AshTypescript.Test.TodoComment
      assert query.action.name == :read
      assert query.page[:limit] == 3
      assert query.page[:count] == true
      refute is_nil(query.filter)
      assert query.sort != []
      assert :id in (query.select || [])
      assert :content in (query.select || [])
      # Extraction template is unchanged by the envelope
      assert template == [:id, {:comments, [:id, :content]}]
    end

    test "bare limit/offset build an unpaged query" do
      raw = [%{"comments" => %{"limit" => 2, "offset" => 1, "fields" => ["id"]}}]

      assert {:ok, {_select, [{:comments, %Ash.Query{} = query}], _template}} =
               process_fields(:read, raw)

      assert query.limit == 2
      assert query.offset == 1
      assert query.page in [nil, false]
    end

    test "fields-only envelope behaves like a plain nested list" do
      raw = [%{"comments" => %{"fields" => ["id"]}}]

      assert {:ok, {_select, [{:comments, %Ash.Query{}}], template}} =
               process_fields(:read, raw)

      assert template == [{:comments, [:id]}]
    end

    test "atom-keyed envelopes are accepted" do
      fields = [%{comments: %{page: %{limit: 1}, fields: [:id]}}]

      assert {:ok, {_s, [{:comments, %Ash.Query{} = query}], _t}} =
               RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, fields)

      assert query.page[:limit] == 1
    end

    test "envelope nests inside an envelope (depth 2 via user -> comments)" do
      raw = [
        %{
          "comments" => %{
            "limit" => 2,
            "fields" => [
              "id",
              %{"user" => ["id", %{"comments" => %{"limit" => 1, "fields" => ["id"]}}]}
            ]
          }
        }
      ]

      assert {:ok, {_s, [{:comments, %Ash.Query{} = outer}], template}} =
               process_fields(:read, raw)

      assert [{:user, user_load}] = outer.load

      # Ash normalizes nested keyword load specs into an %Ash.Query{}; accept
      # either representation and dig out the inner comments query.
      inner =
        case user_load do
          %Ash.Query{load: loads} ->
            Keyword.fetch!(loads, :comments)

          loads when is_list(loads) ->
            loads |> Enum.filter(&is_tuple/1) |> Keyword.fetch!(:comments)
        end

      assert %Ash.Query{limit: 1} = inner
      assert template == [{:comments, [:id, {:user, [:id, {:comments, [:id]}]}]}]
    end

    test "envelope works on a get? read and on a create action" do
      raw = [%{"comments" => %{"limit" => 1, "fields" => ["id"]}}]

      assert {:ok, {_s, [{:comments, %Ash.Query{}}], _t}} =
               process_fields(:get_by_id, raw)

      assert {:ok, {_s, [{:comments, %Ash.Query{}}], _t}} =
               process_fields(:create, raw)
    end

    test "offset-only relationship accepts offset page keys" do
      raw = [
        %{
          "offsetComments" => %{
            "page" => %{"limit" => 2, "offset" => 1, "count" => true},
            "fields" => ["id"]
          }
        }
      ]

      assert {:ok, {_s, [{:offset_comments, %Ash.Query{} = query}], _t}} =
               process_fields(:read, raw)

      assert query.action.name == :read_offset_only
      assert query.page[:limit] == 2
      assert query.page[:offset] == 1
    end

    test "keyset-only relationship accepts keyset page keys" do
      raw = [
        %{
          "keysetComments" => %{
            "page" => %{"limit" => 2, "after" => "cursor"},
            "fields" => ["id"]
          }
        }
      ]

      assert {:ok, {_s, [{:keyset_comments, %Ash.Query{} = query}], _t}} =
               process_fields(:read, raw)

      assert query.action.name == :read_keyset_only
      assert query.page[:limit] == 2
      assert query.page[:after] == "cursor"
    end

    test "many_to_many relationship accepts the full envelope" do
      raw = [
        %{
          "commenters" => %{
            "page" => %{"limit" => 2, "offset" => 0},
            "filter" => %{"name" => %{"eq" => "Bob"}},
            "sort" => "name",
            "fields" => ["id", "name"]
          }
        }
      ]

      assert {:ok, {_s, [{:commenters, %Ash.Query{} = query}], template}} =
               process_fields(:read, raw)

      assert query.resource == AshTypescript.Test.User
      assert query.page[:limit] == 2
      refute is_nil(query.filter)
      assert query.sort != []
      assert template == [{:commenters, [:id, :name]}]
    end
  end

  describe "envelope validation gates" do
    test "envelope on a plain attribute is rejected with kind context" do
      raw = [%{"title" => %{"limit" => 1, "fields" => []}}]

      assert {:error, {:query_opts_on_non_relationship, :title, :attribute, []}} =
               process_fields(:read, raw)
    end

    test "envelope on a to-one relationship is rejected" do
      raw = [%{"user" => %{"limit" => 1, "fields" => ["id"]}}]

      assert {:error, {:query_opts_on_to_one, :user, []}} = process_fields(:read, raw)
    end

    test "args combined with query opts is rejected" do
      raw = [%{"comments" => %{"args" => %{"x" => 1}, "limit" => 1, "fields" => ["id"]}}]

      assert {:error, {:args_and_query_opts_combined, :comments, []}} =
               process_fields(:read, raw)
    end

    test "page on a relationship whose read action has no pagination is rejected" do
      raw = [%{"unpaginatedComments" => %{"page" => %{"limit" => 1}, "fields" => ["id"]}}]

      assert {:error, {:nested_pagination_not_supported, :unpaginated_comments, []}} =
               process_fields(:read, raw)
    end

    test "filter is gated by the relationship's filterable? flag" do
      raw = [
        %{
          "unfilterableComments" => %{
            "filter" => %{"rating" => %{"eq" => 1}},
            "fields" => ["id"]
          }
        }
      ]

      assert {:error, {:filter_not_supported, :unfilterable_comments, :unsupported, []}} =
               process_fields(:read, raw)
    end

    test "filter is gated by the entrypoint's enable_filter? flag" do
      raw = [%{"comments" => %{"filter" => %{"rating" => %{"eq" => 1}}, "fields" => ["id"]}}]

      assert {:error, {:filter_not_supported, :comments, :disabled, []}} =
               process_fields(:read, raw, enable_filter?: false)
    end

    test "sort is gated by the relationship's sortable? flag" do
      raw = [%{"unsortableComments" => %{"sort" => "-rating", "fields" => ["id"]}}]

      assert {:error, {:sort_not_supported, :unsortable_comments, :unsupported, []}} =
               process_fields(:read, raw)
    end

    test "sort is gated by the entrypoint's enable_sort? flag" do
      raw = [%{"comments" => %{"sort" => "-rating", "fields" => ["id"]}}]

      assert {:error, {:sort_not_supported, :comments, :disabled, []}} =
               process_fields(:read, raw, enable_sort?: false)
    end

    test "page combined with bare limit/offset is rejected" do
      raw = [%{"comments" => %{"page" => %{"limit" => 1}, "limit" => 2, "fields" => ["id"]}}]

      assert {:error, {:page_and_limit_offset_combined, :comments, []}} =
               process_fields(:read, raw)
    end

    test "empty or missing fields inside an envelope is rejected" do
      assert {:error, {:requires_field_selection, :relationship, :comments, []}} =
               process_fields(:read, [%{"comments" => %{"limit" => 1, "fields" => []}}])

      assert {:error, {:requires_field_selection, :relationship, :comments, []}} =
               process_fields(:read, [%{"comments" => %{"limit" => 1}}])
    end

    test "unknown page keys for the relationship's pagination kind are rejected" do
      # :comments is mixed, so both key families are allowed — but junk is not
      raw = [%{"comments" => %{"page" => %{"limit" => 1, "bogus" => true}, "fields" => ["id"]}}]

      assert {:error, {:invalid_nested_page, :comments, {:unknown_keys, [:bogus]}, []}} =
               process_fields(:read, raw)
    end

    test "keyset page keys are rejected on an offset-only relationship" do
      raw = [
        %{
          "offsetComments" => %{
            "page" => %{"limit" => 1, "after" => "cursor"},
            "fields" => ["id"]
          }
        }
      ]

      assert {:error, {:invalid_nested_page, :offset_comments, {:unknown_keys, [:after]}, []}} =
               process_fields(:read, raw)
    end

    test "offset page keys are rejected on a keyset-only relationship" do
      raw = [
        %{
          "keysetComments" => %{
            "page" => %{"limit" => 1, "offset" => 2},
            "fields" => ["id"]
          }
        }
      ]

      assert {:error, {:invalid_nested_page, :keyset_comments, {:unknown_keys, [:offset]}, []}} =
               process_fields(:read, raw)
    end

    test "envelope on a relationship to a non-RPC resource is an unknown field" do
      raw = [%{"notExposedItems" => %{"limit" => 1, "fields" => ["id"]}}]

      assert {:error, {:unknown_field, :not_exposed_items, AshTypescript.Test.Todo, []}} =
               process_fields(:read, raw)
    end

    test "error path is populated at depth" do
      raw = [
        %{
          "comments" => %{
            "limit" => 1,
            "fields" => [
              "id",
              %{
                "user" => [
                  "id",
                  %{"comments" => %{"page" => %{"limit" => 1}, "fields" => ["id"]}}
                ]
              }
            ]
          }
        }
      ]

      # user -> comments is paginated (mixed), so use an unpaginatable rel at depth:
      raw_bad = [
        %{
          "comments" => %{
            "limit" => 1,
            "fields" => [
              %{
                "todo" => [
                  "id",
                  %{"unpaginatedComments" => %{"page" => %{"limit" => 1}, "fields" => ["id"]}}
                ]
              }
            ]
          }
        }
      ]

      assert {:ok, _} = process_fields(:read, raw)

      assert {:error,
              {:nested_pagination_not_supported, :unpaginated_comments, [:comments, :todo]}} =
               process_fields(:read, raw_bad)
    end
  end

  describe "error builder coverage" do
    test "every nested/top-level query-opts throw has a dedicated clause" do
      cases = [
        {{:query_opts_on_non_relationship, :title, :attribute, []}, "invalid_query_opts"},
        {{:query_opts_on_to_one, :user, []}, "invalid_query_opts"},
        {{:args_and_query_opts_combined, :comments, []}, "invalid_query_opts"},
        {{:page_and_limit_offset_combined, :comments, []}, "invalid_query_opts"},
        {{:nested_pagination_not_supported, :unpaginated_comments, [:todo]},
         "pagination_not_supported"},
        {{:filter_not_supported, :comments, :disabled, []}, "filter_not_supported"},
        {{:filter_not_supported, :comments, :unsupported, [:todo]}, "filter_not_supported"},
        {{:filter_not_supported, :top_level, :disabled}, "filter_not_supported"},
        {{:sort_not_supported, :comments, :unsupported, []}, "sort_not_supported"},
        {{:sort_not_supported, :top_level, :unsupported}, "sort_not_supported"},
        {{:pagination_not_supported, :top_level, :unsupported}, "pagination_not_supported"},
        {{:invalid_nested_page, :comments, {:unknown_keys, [:bogus]}, []}, "invalid_pagination"}
      ]

      for {throw_tuple, expected_type} <- cases do
        response = AshTypescript.Rpc.ErrorBuilder.build_error_response(throw_tuple)

        assert response.type == expected_type,
               "#{inspect(throw_tuple)} mapped to #{response.type}, expected #{expected_type}"

        refute response.type == "unknown_error"
        assert is_binary(response.message)
        assert Map.has_key?(response.details, :suggestion)
      end
    end

    test "reason lands in details for gated errors" do
      response =
        AshTypescript.Rpc.ErrorBuilder.build_error_response(
          {:filter_not_supported, :comments, :disabled, []}
        )

      assert response.details.reason == :disabled
    end
  end
end
