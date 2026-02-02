# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TupleNewtypeInputTest do
  @moduledoc """
  Tests for NewType tuple with typescript_field_names input parsing.

  This test isolates the tuple NewType casting issue to understand
  where the validation failure occurs.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.InputFormatter
  alias AshTypescript.Rpc.ValueFormatter
  alias AshTypescript.TypeSystem.Introspection

  describe "LocationTuple NewType introspection" do
    test "unwraps correctly with instance_of" do
      type = AshTypescript.Test.InputParsing.LocationTuple

      {unwrapped, constraints} = Introspection.unwrap_new_type(type, [])

      assert unwrapped == Ash.Type.Tuple
      assert constraints[:instance_of] == type
      assert Keyword.has_key?(constraints, :fields)
    end

    test "has typescript_field_names callback" do
      type = AshTypescript.Test.InputParsing.LocationTuple

      assert Introspection.has_typescript_field_names?(type)

      field_names = type.typescript_field_names()
      assert field_names[:lat_1] == "lat1"
      assert field_names[:lng_1] == "lng1"
      assert field_names[:is_verified?] == "isVerified"
    end
  end

  describe "ValueFormatter with LocationTuple" do
    test "formats tuple input correctly (TypeScript names to Elixir names)" do
      type = AshTypescript.Test.InputParsing.LocationTuple
      formatter = :camel_case

      ts_input = %{"lat1" => 37.7749, "lng1" => -122.4194, "isVerified" => true}

      result = ValueFormatter.format(ts_input, type, [], formatter, :input)

      assert result == %{lat_1: 37.7749, lng_1: -122.4194, is_verified?: true}
    end

    test "formats tuple output correctly (Elixir names to TypeScript names)" do
      type = AshTypescript.Test.InputParsing.LocationTuple
      formatter = :camel_case

      elixir_value = %{lat_1: 37.7749, lng_1: -122.4194, is_verified?: true}

      result = ValueFormatter.format(elixir_value, type, [], formatter, :output)

      assert result == %{"lat1" => 37.7749, "lng1" => -122.4194, "isVerified" => true}
    end
  end

  describe "InputFormatter with LocationTuple attribute" do
    test "formats input with tuple attribute" do
      resource = AshTypescript.Test.InputParsing.Resource
      action = Ash.Resource.Info.action(resource, :create)
      formatter = :camel_case

      raw_input = %{
        "userName" => "tuple_user",
        "emailAddress" => "tuple@example.com",
        "location" => %{
          "lat1" => 37.7749,
          "lng1" => -122.4194,
          "isVerified" => true
        }
      }

      {:ok, formatted} = InputFormatter.format(raw_input, resource, action, formatter)

      # Check that tuple field names are converted correctly
      assert formatted.user_name == "tuple_user"
      assert formatted.email_address == "tuple@example.com"
      assert formatted.location == %{lat_1: 37.7749, lng_1: -122.4194, is_verified?: true}
    end
  end

  describe "Ash.Type.Tuple casting behavior" do
    test "compares with Todo coordinates - inline tuple attribute works via RPC" do
      # The RPC test for Todo coordinates DOES work
      # This test verifies the input value is correctly formatted
      resource = AshTypescript.Test.Todo
      attr = Ash.Resource.Info.attribute(resource, :coordinates)

      # Check attribute setup (Ash.Type.Tuple is the module name)
      assert attr.type == Ash.Type.Tuple
      assert Keyword.has_key?(attr.constraints, :fields)
    end

    test "Todo coordinates cast via changeset - must use tuple not map" do
      # Tuples must be passed as actual Elixir tuples, not maps
      # The RPC pipeline converts maps to tuples before passing to changeset
      resource = AshTypescript.Test.Todo

      # First create a user for the Todo
      user = %AshTypescript.Test.User{
        id: Ash.UUID.generate(),
        name: "Test",
        email: "test@test.com"
      }

      # IMPORTANT: coordinates must be an actual tuple, not a map
      # The field order is defined by the constraints: latitude, longitude
      params = %{
        title: "Test",
        user_id: user.id,
        # <-- Actual Elixir tuple!
        coordinates: {37.7749, -122.4194}
      }

      changeset = Ash.Changeset.for_create(resource, :create, params)

      # Check if coordinates attribute was set
      coords = Ash.Changeset.get_attribute(changeset, :coordinates)

      if changeset.valid? do
        # After casting, tuple REMAINS a tuple - access via elem()
        # Field order: latitude (0), longitude (1)
        assert elem(coords, 0) == 37.7749
        assert elem(coords, 1) == -122.4194
      else
        # If it fails, show detailed errors
        flunk("Todo changeset failed: #{inspect(changeset.errors)}")
      end
    end

    test "LocationTuple NewType has correct subtype" do
      type = AshTypescript.Test.InputParsing.LocationTuple

      assert Ash.Type.NewType.new_type?(type)

      # Check what subtype_of returns
      subtype = Ash.Type.NewType.subtype_of(type)
      # The subtype should be Ash.Type.Tuple (module), not :tuple (atom)
      assert subtype == Ash.Type.Tuple
    end

    test "LocationTuple constraints are correctly initialized" do
      type = AshTypescript.Test.InputParsing.LocationTuple
      {:ok, constraints} = type.do_init([])

      assert Keyword.has_key?(constraints, :fields)
      fields = constraints[:fields]

      assert Keyword.has_key?(fields, :lat_1)
      assert Keyword.has_key?(fields, :lng_1)
      assert Keyword.has_key?(fields, :is_verified?)
    end

    test "LocationTuple rejects map input - requires actual tuple" do
      type = AshTypescript.Test.InputParsing.LocationTuple
      {:ok, constraints} = Ash.Type.init(type, [])

      # Maps are NOT valid input for tuple types - must be actual tuples
      # The RPC pipeline's convert_map_to_tuple handles this conversion
      map_inputs = [
        %{lat_1: 37.7749, lng_1: -122.4194, is_verified?: true},
        %{"lat_1" => 37.7749, "lng_1" => -122.4194, "is_verified?" => true}
      ]

      for input <- map_inputs do
        result = Ash.Type.cast_input(type, input, constraints)
        assert {:error, _} = result, "Expected map input to be rejected"
      end

      # Actual tuple should work
      {:ok, cast_value} = Ash.Type.cast_input(type, {37.7749, -122.4194, true}, constraints)
      assert is_tuple(cast_value)
    end

    test "direct Ash.Type.Tuple cast with inline constraints - requires actual tuple" do
      # Ash.Type.Tuple.cast_input expects an actual Elixir tuple, not a map
      constraints = [
        fields: [
          lat_1: [type: :float, allow_nil?: false],
          lng_1: [type: :float, allow_nil?: false],
          is_verified?: [type: :boolean, allow_nil?: true]
        ]
      ]

      # Input must be an actual Elixir tuple in field order
      input = {37.7749, -122.4194, true}

      result = Ash.Type.cast_input(Ash.Type.Tuple, input, constraints)

      case result do
        {:ok, cast_value} ->
          # After casting, tuple REMAINS a tuple - access via elem()
          # Field order: lat_1 (0), lng_1 (1), is_verified? (2)
          assert is_tuple(cast_value)
          assert elem(cast_value, 0) == 37.7749
          assert elem(cast_value, 1) == -122.4194
          assert elem(cast_value, 2) == true

        {:error, error} ->
          flunk("Direct cast failed: #{inspect(error)}")
      end
    end
  end

  describe "full changeset creation with tuple attribute" do
    test "creates changeset with tuple value - requires actual tuple" do
      resource = AshTypescript.Test.InputParsing.Resource

      # IMPORTANT: location must be an actual Elixir tuple, not a map
      # The RPC pipeline's convert_map_to_tuple handles this conversion
      # Field order: lat_1 (0), lng_1 (1), is_verified? (2)
      params = %{
        user_name: "tuple_user",
        email_address: "tuple@example.com",
        location: {37.7749, -122.4194, true}
      }

      changeset = Ash.Changeset.for_create(resource, :create, params)

      # Check if the location attribute was set correctly
      location = Ash.Changeset.get_attribute(changeset, :location)

      if changeset.valid? do
        # After casting, tuple REMAINS a tuple - access via elem()
        assert is_tuple(location)
        assert elem(location, 0) == 37.7749
        assert elem(location, 1) == -122.4194
        assert elem(location, 2) == true
      else
        # If invalid, show the errors for debugging
        flunk("Changeset invalid: #{inspect(changeset.errors)}")
      end
    end
  end
end
