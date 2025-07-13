defmodule AshTypescript.Helpers do
  def snake_to_pascal_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_pascal_case()
  end

  def snake_to_pascal_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {part, _} -> String.capitalize(part) end)
    |> Enum.join()
  end

  def snake_to_camel_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_camel_case()
  end

  def snake_to_camel_case(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
    |> Enum.join()
  end

  def camel_to_snake_case(camel) when is_atom(camel) do
    camel
    |> Atom.to_string()
    |> camel_to_snake_case()
  end

  def camel_to_snake_case(camel) when is_binary(camel) do
    camel
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  def pascal_to_snake_case(pascal) when is_atom(pascal) do
    pascal
    |> Atom.to_string()
    |> pascal_to_snake_case()
  end

  def pascal_to_snake_case(pascal) when is_binary(pascal) do
    pascal
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  def snake_to_kebab_case(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_kebab_case()
  end

  def snake_to_kebab_case(snake) when is_binary(snake) do
    String.replace(snake, "_", "-")
  end

  def kebab_to_snake_case(kebab) when is_atom(kebab) do
    kebab
    |> Atom.to_string()
    |> kebab_to_snake_case()
  end

  def kebab_to_snake_case(kebab) when is_binary(kebab) do
    String.replace(kebab, "-", "_")
  end
end
