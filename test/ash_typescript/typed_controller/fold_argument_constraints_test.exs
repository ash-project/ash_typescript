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

  test "invalid returns constraints raise a DslError at compile time" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        defmodule ControllerWithInvalidReturnConstraints do
          use AshTypescript.TypedController

          typed_controller do
            module_name(AshTypescript.Test.InvalidReturnConstraintsController)

            post :login do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              returns :map
              constraints bogus: true
            end
          end
        end
      end

    assert error.message =~ "Invalid constraints for `returns` of route `login`"
    assert error.message =~ ":map"
  end

  test "a returns type that is not an Ash type raises a DslError at compile time" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        defmodule ControllerWithInvalidReturnType do
          use AshTypescript.TypedController

          typed_controller do
            module_name(AshTypescript.Test.InvalidReturnTypeController)

            post :login do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              returns {:array, :not_a_real_type}
            end
          end
        end
      end

    assert error.message =~ "Invalid `returns` type for route `login`"
    assert error.message =~ ":not_a_real_type"
  end

  test "an argument type that is not an Ash type raises a DslError at compile time" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        defmodule ControllerWithInvalidArgumentType do
          use AshTypescript.TypedController

          typed_controller do
            module_name(AshTypescript.Test.InvalidArgumentTypeController)

            post :login do
              run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
              argument :code, :not_a_real_type
            end
          end
        end
      end

    assert error.message =~ "Invalid type for argument `code`"
  end

  describe "returns type restrictions" do
    # Handlers decide what they send, so the caller cannot select fields of a
    # resource; unions only have field-selection output shapes. Both are
    # rejected at any depth.

    test "rejects a resource" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule ControllerReturningResource do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.ReturningResourceController)

              get :todo do
                run fn conn, _params -> conn end
                returns :struct
                constraints instance_of: AshTypescript.Test.Todo
              end
            end
          end
        end

      assert error.message =~ "Unsupported `returns` type for route `todo`"
      assert error.message =~ "resource AshTypescript.Test.Todo is not supported"
    end

    test "rejects an embedded resource nested inside a typed map array" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule ControllerReturningNestedEmbedded do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.ReturningNestedEmbeddedController)

              get :tasks do
                run fn conn, _params -> conn end
                returns {:array, :map}

                constraints items: [
                              fields: [metadata: [type: AshTypescript.Test.TaskMetadata]]
                            ]
              end
            end
          end
        end

      assert error.message =~ "at `[].metadata`"
      assert error.message =~ "resource AshTypescript.Test.TaskMetadata is not supported"
    end

    test "rejects a union" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule ControllerReturningUnion do
            use AshTypescript.TypedController

            typed_controller do
              module_name(AshTypescript.Test.ReturningUnionController)

              get :value do
                run fn conn, _params -> conn end
                returns :union

                constraints types: [
                              text: [type: :string],
                              number: [type: :integer]
                            ]
              end
            end
          end
        end

      assert error.message =~ "union types are not supported"
    end
  end

  test "returns constraints are folded, including nested field constraints" do
    route =
      AshTypescript.Test.Session
      |> Spark.Dsl.Extension.get_entities([:typed_controller])
      |> Enum.find(&(&1.name == :search))

    assert route.returns == {:array, :map}
    assert Keyword.get(route.constraints, :nil_items?) == false

    fields = route.constraints |> Keyword.fetch!(:items) |> Keyword.fetch!(:fields)
    # `Ash.Type.init/2` resolves nested field types, as it does for Ash actions
    assert Keyword.fetch!(fields, :id)[:type] == Ash.Type.UUID
  end

  test "NewType argument constraints are initialized with the type's own constraints" do
    route =
      AshTypescript.Test.Session
      |> Spark.Dsl.Extension.get_entities([:typed_controller])
      |> Enum.find(&(&1.name == :update_provider))

    # Without `Ash.Type.init/2` a NewType's `fields` never reach casting, so
    # nested values (e.g. atom enums) would be passed through uncast
    assert route.returns == AshTypescript.Test.CustomMetadata
    assert route.constraints |> Keyword.fetch!(:fields) |> Keyword.has_key?(:is_active?)
  end

  test "routes without returns keep empty constraints" do
    route =
      AshTypescript.Test.Session
      |> Spark.Dsl.Extension.get_entities([:typed_controller])
      |> Enum.find(&(&1.name == :logout))

    assert route.returns == nil
    assert route.constraints == []
  end
end
