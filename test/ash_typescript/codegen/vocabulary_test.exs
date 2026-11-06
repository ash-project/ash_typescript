# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.VocabularyTest do
  # Codegen names the request keys and filter keys with ash_rpc's vocabulary
  # (`AshRpc.Manifest.vocabulary/1`), the keys the runtime accepts; the
  # response and client-only keys keep the output formatter, pinned here
  # against an ash_rpc response.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Codegen.FilterTypes
  alias AshTypescript.Helpers
  alias AshTypescript.Test.{CodegenTestHelper, TestHelpers}

  # `Helpers.formatted_<key>_field/0` for each request key, by vocabulary scope.
  @request_keys [
    params: [
      :action,
      :input,
      :identity,
      :fields,
      :get_by,
      :filter,
      :sort,
      :page,
      :tenant,
      :metadata_fields
    ],
    page: [:limit, :offset, :count, :after, :before]
  ]

  # The `:filter_ops` names codegen doesn't type as a field operator or
  # function: the connectives (typed as `and`/`or`/`not` arrays), `input`, the
  # operator aliases and every other builtin operator and function. A new Ash
  # operator or function fails "every :filter_ops name is typed or
  # deliberately untyped" until it is typed or listed here.
  @untyped [:and, :or, :not, :input] ++
             [:equals, :not_equals, :gt, :lt, :gte, :lte] ++
             [:-, :ago, :at, :composite_type, :concat, :count_nils, :date_add] ++
             [:datetime_add, :div, :error, :fragment, :from_now, :get_path, :if] ++
             [:intersects, :is_distinct_from, :is_not_distinct_from, :lazy, :length] ++
             [:minus, :now, :plus, :range_adjacent, :range_contains, :range_lower] ++
             [:range_overlaps, :range_upper, :rem, :round, :start_of_day] ++
             [:string_downcase, :string_join, :string_length, :string_position] ++
             [:string_split, :string_trim, :times, :today, :type]

  defp pascal,
    do:
      AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

  describe "ClientNames.vocabulary!" do
    test "vocabulary!/3 returns ash_rpc's client name" do
      assert ClientNames.vocabulary!(AshTypescript.manifest(), :params, :get_by) == "getBy"
      assert ClientNames.vocabulary!(pascal(), :params, :get_by) == "GetBy"
      assert ClientNames.vocabulary!(pascal(), :page, :limit) == "Limit"
      assert ClientNames.vocabulary!(pascal(), :filter_ops, :not_eq) == "NotEq"

      assert_raise ArgumentError, "no client name for :nope in the :params vocabulary", fn ->
        ClientNames.vocabulary!(AshTypescript.manifest(), :params, :nope)
      end
    end

    test "vocabulary!/2 reads the current manifest, with_manifest/2 included" do
      assert ClientNames.vocabulary!(:params, :get_by) == "getBy"

      assert AshTypescript.with_manifest(pascal(), fn ->
               ClientNames.vocabulary!(:params, :get_by)
             end) == "GetBy"
    end
  end

  describe "request keys" do
    test "every request key codegen emits is in the vocabulary" do
      for manifest <- [AshTypescript.manifest(), pascal()] do
        AshTypescript.with_manifest(manifest, fn ->
          for {scope, keys} <- @request_keys, key <- keys do
            assert apply(Helpers, :"formatted_#{key}_field", []) ==
                     ClientNames.vocabulary!(manifest, scope, key),
                   "formatted_#{key}_field/0 under #{AshTypescript.output_field_formatter()}"
          end
        end)
      end
    end

    # Nested-load envelopes (`{ comments: { fields, filter, sort, page, limit,
    # offset } }`) and calculation loads (`{ args, fields }`) are read by
    # ash_rpc under `:query_opts`. Its client names equal the `:params` ones
    # (one formatter names both), so the tests trace which scope codegen asks.
    test "nested-load and calculation-load keys come from the :query_opts vocabulary" do
      calls =
        trace_calls([{ClientNames, :vocabulary!}], fn ->
          AshTypescript.Codegen.UtilityTypes.generate_utility_types()
        end)

      keys = for {_mfa, [:query_opts, key], _caller} <- calls, uniq: true, do: key
      query_opts = AshRpc.Manifest.vocabulary(AshTypescript.manifest()).query_opts

      assert Enum.sort(keys) == Enum.sort(Map.values(query_opts))
      # The utility types have no top-level request key.
      assert for({_mfa, [:params, key], _caller} <- calls, do: key) == []
    end

    test "a typed query's calculation load names args and fields by :query_opts" do
      typed_queries = AshTypescript.Rpc.Codegen.FunctionGenerators.TypedQueries

      calls =
        trace_calls(
          [
            {Helpers, :formatted_query_opt_field},
            {Helpers, :formatted_fields_field}
          ],
          fn -> {:ok, _} = CodegenTestHelper.generate_all_content() end
        )

      from_typed_queries =
        for {f, args, {^typed_queries, _, _}} <- calls, uniq: true, do: {f, args}

      # Calculation loads (`args`, `fields`) and relationship envelopes (the
      # list_todos_keyword_envelope and list_todos_map_envelope typed queries)
      assert Enum.sort(from_typed_queries) ==
               for(
                 key <- [:args, :fields, :filter, :limit, :offset, :page, :sort],
                 do: {:formatted_query_opt_field, [key]}
               )
    end

    test "static_client_names/0 holds no request key" do
      request = for {_scope, keys} <- @request_keys, key <- keys, key != :fields, do: key

      assert Helpers.static_client_names() -- request == Helpers.static_client_names()
    end

    test "run_typed_query/4 sends vocabulary keys" do
      result =
        AshTypescript.run_typed_query(
          :list_todos_user_page,
          %{page: %{"Limit" => 1, "Offset" => 0}},
          %Plug.Conn{},
          manifest: pascal()
        )

      assert %{"Success" => true, "Data" => %{"Limit" => 1, "Results" => _}} = result
    end
  end

  describe "response keys" do
    setup do
      user =
        AshTypescript.Test.User
        |> Ash.Changeset.for_create(:create, %{
          name: "Vocabulary",
          email: "vocab-#{System.unique_integer([:positive])}@example.com"
        })
        |> Ash.create!()

      todo =
        AshTypescript.Test.Todo
        |> Ash.Changeset.for_create(:create, %{title: "Vocabulary", user_id: user.id})
        |> Ash.create!()

      AshTypescript.Test.TodoComment
      |> Ash.Changeset.for_create(:create, %{
        content: "Vocabulary",
        author_name: "Vocabulary",
        rating: 5,
        is_helpful: true,
        todo_id: todo.id,
        user_id: user.id
      })
      |> Ash.create!()

      :ok
    end

    defp run(params),
      do:
        AshRpc.run_action(AshTypescript.RpcProfile, TestHelpers.build_rpc_conn(), params,
          manifest: pascal()
        )

    defp keys(map), do: map |> Map.keys() |> Enum.sort()

    test "response keys match ash_rpc's response" do
      offset =
        run(%{
          "Action" => "list_todos",
          "Fields" => ["Id"],
          "Page" => %{"Limit" => 1, "Offset" => 0, "Count" => true}
        })

      keyset =
        run(%{
          "Action" => "list_todo_comments_keyset",
          "Fields" => ["Id"],
          "Page" => %{"Limit" => 1, "Count" => true}
        })

      AshTypescript.with_manifest(pascal(), fn ->
        assert keys(offset) ==
                 Enum.sort([Helpers.formatted_success_field(), Helpers.formatted_data_field()])

        assert offset[Helpers.formatted_success_field()] == true

        assert keys(offset[Helpers.formatted_data_field()]) ==
                 Enum.sort([
                   Helpers.formatted_results_field(),
                   Helpers.formatted_has_more_field(),
                   Helpers.formatted_limit_field(),
                   Helpers.formatted_offset_field(),
                   Helpers.formatted_count_field(),
                   Helpers.formatted_error_type_field()
                 ])

        assert keys(keyset[Helpers.formatted_data_field()]) ==
                 Enum.sort([
                   Helpers.formatted_results_field(),
                   Helpers.formatted_has_more_field(),
                   Helpers.formatted_limit_field(),
                   Helpers.formatted_after_field(),
                   Helpers.formatted_before_field(),
                   Helpers.formatted_previous_page_field(),
                   Helpers.formatted_next_page_field(),
                   Helpers.formatted_count_field(),
                   Helpers.formatted_error_type_field()
                 ])
      end)
    end

    # `errorId` is only on internal errors, which this request isn't.
    test "error keys match ash_rpc's failure response" do
      failure = run(%{"Action" => "no_such_action", "Fields" => ["Id"]})

      AshTypescript.with_manifest(pascal(), fn ->
        assert keys(failure) ==
                 Enum.sort([Helpers.formatted_success_field(), Helpers.formatted_errors_field()])

        assert failure[Helpers.formatted_success_field()] == false
        [error | _] = failure[Helpers.formatted_errors_field()]

        assert keys(error) ==
                 Enum.sort([
                   Helpers.formatted_error_type_field(),
                   Helpers.formatted_error_message_field(),
                   Helpers.formatted_error_short_message_field(),
                   Helpers.formatted_error_vars_field(),
                   Helpers.formatted_error_fields_field(),
                   Helpers.formatted_error_path_field(),
                   Helpers.formatted_error_details_field()
                 ])
      end)
    end
  end

  describe "filter keys" do
    test "every :filter_ops name is typed or deliberately untyped" do
      names = AshTypescript.manifest() |> AshRpc.Manifest.vocabulary() |> Map.fetch!(:filter_ops)

      assert Enum.sort(Map.values(names) -- FilterTypes.typed_filter_ops()) == Enum.sort(@untyped)
    end

    test "filter keys are vocabulary client names" do
      {:ok, content} = CodegenTestHelper.generate_all_content(:ash_typescript, manifest: pascal())
      [_, filter] = String.split(content, "export type TodoFilterInput = {", parts: 2)
      [filter | _] = String.split(filter, "\n};", parts: 2)

      assert filter =~ "  And?: Array<TodoFilterInput>;"
      assert filter =~ ~r/\n  Title\?: \{\n    Eq\?: string;\n    NotEq\?: string;/
      assert filter =~ "    LessThan?: "
      assert filter =~ "    IsNil?: boolean;"
      assert filter =~ "    Contains?: string;"
      assert filter =~ "    StringStartsWith?: string;"
      refute filter =~ "    eq?: "
    end
  end

  # `{function, args, caller}` of every call `fun` makes to the `functions`
  # (`{module, name}`). A process can't be its own tracer: the messages go to
  # a collector.
  defp trace_calls(functions, fun) do
    test = self()

    collector =
      spawn_link(fn ->
        receive do
          :go -> send(test, {:calls, collect_calls([])})
        end
      end)

    # A pattern only applies to loaded modules; without this, a test run on
    # its own traces nothing.
    for {module, _function} <- functions, do: Code.ensure_loaded!(module)

    match_spec = [{:_, [], [{:message, {:caller}}]}]
    for mf <- functions, do: :erlang.trace_pattern(Tuple.append(mf, :_), match_spec, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, collector}])

    try do
      fun.()
    after
      :erlang.trace(self(), false, [:call])
      for mf <- functions, do: :erlang.trace_pattern(Tuple.append(mf, :_), false, [:local])
    end

    ref = :erlang.trace_delivered(self())

    receive do
      {:trace_delivered, _pid, ^ref} -> send(collector, :go)
    end

    receive do
      {:calls, calls} -> calls
    end
  end

  defp collect_calls(acc) do
    receive do
      {:trace, _pid, :call, {_m, f, args}, caller} -> collect_calls([{f, args, caller} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
