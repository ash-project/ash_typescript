# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.RelationshipQueryCapabilitiesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.Custom

  defp rel(resource, name) do
    Ash.Info.Manifest.get_relationship(AshTypescript.resource_lookup(), resource, name)
  end

  test "many-relationship to an RPC resource is stamped with pagination and read_action" do
    rel = rel(AshTypescript.Test.Todo, :comments)
    assert Custom.relationship_pagination(rel) == :mixed
    assert Custom.relationship_read_action(rel) == :read
  end

  test "relationship read_action override drives the pagination derivation" do
    rel = rel(AshTypescript.Test.Todo, :unpaginated_comments)
    assert Custom.relationship_pagination(rel) == :none
    assert Custom.relationship_read_action(rel) == :read_unpaginated
  end

  test "filterable?/sortable? flags are carried on the manifest relationship itself" do
    refute rel(AshTypescript.Test.Todo, :unfilterable_comments).filterable?
    refute rel(AshTypescript.Test.Todo, :unsortable_comments).sortable?
    assert rel(AshTypescript.Test.Todo, :comments).filterable?
    assert rel(AshTypescript.Test.Todo, :comments).sortable?
  end

  test "pure offset/keyset pagination variants are decorated" do
    offset_rel = rel(AshTypescript.Test.Todo, :offset_comments)
    assert Custom.relationship_pagination(offset_rel) == :offset
    assert Custom.relationship_read_action(offset_rel) == :read_offset_only

    keyset_rel = rel(AshTypescript.Test.Todo, :keyset_comments)
    assert Custom.relationship_pagination(keyset_rel) == :keyset
    assert Custom.relationship_read_action(keyset_rel) == :read_keyset_only
  end

  test "many_to_many relationships are stamped like has_many" do
    rel = rel(AshTypescript.Test.Todo, :commenters)
    assert rel.cardinality == :many
    # User's primary read is a `defaults [:read]`, which carries Ash's
    # data-layer default pagination (offset + keyset).
    assert Custom.relationship_pagination(rel) == :mixed
    assert Custom.relationship_read_action(rel) == :read
  end

  test "to-one relationships are not stamped" do
    rel = rel(AshTypescript.Test.Todo, :user)
    assert Custom.relationship_pagination(rel) == :none
    assert Custom.relationship_read_action(rel) == nil
  end

  test "many-relationships to non-RPC destinations are not stamped" do
    rel = rel(AshTypescript.Test.Todo, :not_exposed_items)
    assert Custom.relationship_pagination(rel) == :none
    assert Custom.relationship_read_action(rel) == nil
  end
end
