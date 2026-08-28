# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.RelationshipMarkersTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  defp find_line(content, regex) do
    content
    |> String.split("\n")
    |> Enum.filter(&(&1 =~ regex))
  end

  test "paginated filterable sortable relationship gets all three markers", %{content: content} do
    assert content =~ ~s(__pagination: "mixed";)

    # Several resources have a `comments` relationship — pin to Todo's, whose
    # destination is TodoComment.
    [comments_line | _] =
      find_line(
        content,
        ~r/^\s*comments: \{ __type: "Relationship"; __array: true; __resource: TodoCommentResourceSchema;/
      )

    assert comments_line =~ ~s(__pagination: "mixed";)
    assert comments_line =~ "__filterInput: TodoCommentFilterInput;"
    assert comments_line =~ "__sortField: TodoCommentSortField;"
  end

  test "unfilterable relationship omits only __filterInput", %{content: content} do
    [line | _] = find_line(content, ~r/^\s*unfilterableComments:/)

    refute line =~ "__filterInput"
    assert line =~ "__sortField: TodoCommentSortField;"
    assert line =~ ~s(__pagination: "mixed";)
  end

  test "unsortable relationship omits only __sortField", %{content: content} do
    [line | _] = find_line(content, ~r/^\s*unsortableComments:/)

    refute line =~ "__sortField"
    assert line =~ "__filterInput: TodoCommentFilterInput;"
  end

  test "unpaginated relationship omits only __pagination", %{content: content} do
    [line | _] = find_line(content, ~r/^\s*unpaginatedComments:/)

    refute line =~ "__pagination"
    assert line =~ "__filterInput: TodoCommentFilterInput;"
  end

  test "pure pagination variants get the matching __pagination marker", %{content: content} do
    [offset_line | _] = find_line(content, ~r/^\s*offsetComments:/)
    assert offset_line =~ ~s(__pagination: "offset";)

    [keyset_line | _] = find_line(content, ~r/^\s*keysetComments:/)
    assert keyset_line =~ ~s(__pagination: "keyset";)
  end

  test "many_to_many relationships get markers like has_many", %{content: content} do
    [line | _] = find_line(content, ~r/^\s*commenters:/)

    assert line =~ ~s(__type: "Relationship"; __array: true;)
    assert line =~ ~s(__pagination: "mixed";)
    assert line =~ "__filterInput: UserFilterInput;"
    assert line =~ "__sortField: UserSortField;"
  end

  test "Fields types carry the action's enable flags", %{content: content} do
    # enable_filter?: false, enable_sort?: true
    assert content =~
             "export type ListTodosNoFilterFields = UnifiedFieldSelection<TodoResourceSchema, false, true>[];"

    # enable_sort?: false, enable_filter?: true
    assert content =~
             "export type ListTodosNoSortFields = UnifiedFieldSelection<TodoResourceSchema, true, false>[];"

    # both disabled
    assert content =~
             "export type ListTodosNoFilterNoSortFields = UnifiedFieldSelection<TodoResourceSchema, false, false>[];"

    # defaults stay bare (source compatibility)
    assert content =~
             "export type ListTodosFields = UnifiedFieldSelection<TodoResourceSchema>[];"
  end

  test "to-one relationships never get markers", %{content: content} do
    lines = find_line(content, ~r/^\s*user: \{ __type: "Relationship";/)

    assert lines != []
    refute Enum.any?(lines, &(&1 =~ "__pagination"))
    refute Enum.any?(lines, &(&1 =~ "__filterInput"))
    refute Enum.any?(lines, &(&1 =~ "__sortField"))
  end
end
