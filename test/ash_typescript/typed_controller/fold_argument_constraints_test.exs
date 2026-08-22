# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.FoldArgumentConstraintsTest do
  @moduledoc """
  Pins the compile-time half of the typed-controller argument semantics:
  the `FoldArgumentConstraints` transformer validates route-argument
  constraints against `Ash.Type.constraints/1` (invalid constraints are
  compile errors, exactly as in Ash) and folds type defaults so downstream
  consumers (request handler, route Zod schemas) see explicit values.
  """

  use ExUnit.Case, async: true

  test "invalid argument constraints raise a DslError at compile time" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        defmodule ControllerWithInvalidConstraints do
          use AshTypescript.TypedController

          typed_controller do
            module_name(AshTypescript.Test.InvalidConstraintsController)

            route :login do
              method(:post)
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              argument :code, :string, constraints: [bogus: true]
            end
          end
        end
      end

    assert error.message =~ "Invalid constraints for argument `code`"
    assert error.message =~ ":string"
  end

  test "valid constraints are folded with type defaults made explicit" do
    defmodule ControllerWithFoldedConstraints do
      use AshTypescript.TypedController

      typed_controller do
        module_name(AshTypescript.Test.FoldedConstraintsController)

        route :rename do
          method(:post)
          run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
          argument :name, :string, constraints: [min_length: 3]
        end
      end
    end

    [route] =
      Spark.Dsl.Extension.get_entities(ControllerWithFoldedConstraints, [:typed_controller])

    [argument] = route.arguments

    # The declared constraint survives folding...
    assert argument.constraints[:min_length] == 3
    # ...and the string type's defaults become explicit, which is what drives
    # runtime trimming/""->nil and the derived min(1) in route Zod schemas.
    assert argument.constraints[:allow_empty?] == false
    assert argument.constraints[:trim?] == true
  end

  test "array arguments fold item constraints and survive runtime casting" do
    route =
      AshTypescript.Test.Session
      |> Spark.Dsl.Extension.get_entities([:typed_controller])
      |> Enum.find(&(&1.name == :search))

    tags = Enum.find(route.arguments, &(&1.name == :tags))

    assert tags.type == {:array, :string}

    # The outer array constraints gain their defaults, and the declared item
    # constraints are folded with the string defaults made explicit
    assert Keyword.get(tags.constraints, :nil_items?) == false
    items = Keyword.fetch!(tags.constraints, :items)
    assert Keyword.get(items, :min_length) == 2
    assert Keyword.get(items, :allow_empty?) == false
    assert Keyword.get(items, :trim?) == true

    type = Ash.Type.get_type(tags.type)

    assert {:ok, cast} = Ash.Type.cast_input(type, ["elixir", " ash "], tags.constraints)

    # Trimming is an item constraint, so it lands in apply_constraints
    assert {:ok, ["elixir", "ash"]} = Ash.Type.apply_constraints(type, cast, tags.constraints)

    # Item constraints are enforced, not decorative
    assert {:error, _} =
             Ash.Type.apply_constraints(type, ["a"], tags.constraints)
  end
end
