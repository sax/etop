defmodule Etop.Utils do
  @moduledoc """
  Utility helpers for Etop.
  """

  @doc """
  Center the given string in the given length.

  Return a string of length >= the given length with the given string centered.

  The returned string is padded (leading and trailing) with the given padding (default " ")

  ## Examples

      iex> Etop.Utils.center("Test", 8)
      "  Test  "

      iex> Etop.Utils.center('Test', 7, "-")
      "-Test--"
  """
  @spec center(any(), integer(), String.t()) :: String.t()
  def center(item, len, char \\ " ")

  def center(item, len, char) when is_binary(item) do
    str_len = String.length(item)

    len1 = if str_len < len, do: div(len - str_len, 2) + str_len, else: 0

    item |> pad(len1, char) |> pad_t(len, char)
  end

  def center(item, len, char), do: item |> to_string() |> center(len, char)

  @doc """
  Returns the server's local naive datetime with the microsecond field truncated to the
  given precision (:microsecond, :millisecond or :second).

  ## Arguments
    * datetime (default utc_now)
    * precision (default :second)

  ## Examples

      iex> datetime = Etop.Utils.local_time()
      iex> datetime.year >= 2020
      true

      iex> datetime = Etop.Utils.local_time(:millisecond)
      iex> elem(datetime.microsecond, 1)
      3

      iex> datetime = NaiveDateTime.utc_now()
      iex> expected = NaiveDateTime.add(datetime, Etop.Utils.timezone_offset())
      iex> Etop.Utils.local_time(datetime) == %{expected | microsecond: {0, 0}}
      true

      iex> datetime = NaiveDateTime.utc_now()
      iex> expected = NaiveDateTime.add(datetime, Etop.Utils.timezone_offset())
      iex> Etop.Utils.local_time(datetime, :microsecond) == expected
      true
  """
  @spec local_time(DateTime.t() | NaiveDateTime.t(), atom()) :: NaiveDateTime.t()
  def local_time(datetime \\ NaiveDateTime.utc_now(), precision \\ :second)

  def local_time(%NaiveDateTime{} = datetime, precision) do
    datetime
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!()
    |> Map.put(:microsecond, datetime.microsecond)
    |> NaiveDateTime.truncate(precision)
  end

  def local_time(%DateTime{} = datetime, precision) do
    datetime
    |> DateTime.to_naive()
    |> local_time(precision)
  end

  def local_time(precision, _) when is_atom(precision) do
    local_time(NaiveDateTime.utc_now(), precision)
  end

  @doc """
  Pad (leading) the given string with spaces for the given length.

  ## Examples

      iex> Etop.Utils.pad("Test", 8)
      "    Test"

      iex> Etop.Utils.pad("Test", 2)
      "Test"

      iex> Etop.Utils.pad(100, 4, "0")
      "0100"
  """
  @spec pad(any(), integer(), String.t()) :: String.t()
  def pad(string, len, char \\ " ")
  def pad(string, len, char) when is_binary(string), do: String.pad_leading(string, len, char)
  def pad(item, len, char), do: item |> to_string() |> pad(len, char)

  @doc """
  Pad (trailing) the given string with spaces for the given length.

  ## Examples

      iex> Etop.Utils.pad_t("Test", 8)
      "Test    "

      iex> Etop.Utils.pad_t("Test", 2)
      "Test"

      iex> Etop.Utils.pad_t(10.1, 5, "0")
      "10.10"
  """
  @spec pad_t(any(), integer(), String.t()) :: String.t()
  def pad_t(string, len, char \\ " ")
  def pad_t(string, len, char) when is_binary(string), do: String.pad_trailing(string, len, char)
  def pad_t(item, len, char), do: item |> to_string() |> pad_t(len, char)

  @doc """
  Configurable sort.

  ## Arguments

  * `list` - the enumerable to be sorted.
  * `field` (:reductions_diff) - the field to be sorted on.
  * `field_fn` (fn field -> &elem(&1, 1)[field] end) - function to get the field.
  * `sorter_fn` (&>/2) -> Sort comparator (default descending)

  ## Examples

      iex> data = [one: %{a: 3, b: 2}, two: %{a: 1, b: 3}]
      iex> Etop.Utils.sort(data, :b)
      [two: %{a: 1, b: 3}, one: %{a: 3, b: 2}]

      iex> data = [one: %{a: 3, b: 2}, two: %{a: 1, b: 3}]
      iex> Etop.Utils.sort(data, :a, sorter: &<=/2)
      [two: %{a: 1, b: 3}, one: %{a: 3, b: 2}]

      iex> data = [%{a: 1, b: 2}, %{a: 2, b: 3}]
      iex> Etop.Utils.sort(data, :a, mapper: & &1[:a])
      [%{a: 2, b: 3}, %{a: 1, b: 2}]

      iex> data = [x: %{a: 1, b: 1}, y: %{a: 1, b: 2}, z: %{a: 2, b: 0}]
      iex> Etop.Utils.sort(data, :a, secondary: :b)
      [z: %{a: 2, b: 0}, y: %{a: 1, b: 2}, x: %{a: 1, b: 1}]
  """
  def sort(list, field, opts \\ []) do
    mapper = sort_mapper(field, opts[:mapper], opts[:secondary])
    sorter = opts[:sorter] || (&>/2)
    Enum.sort_by(list, mapper, sorter)
  end

  defp sort_mapper(field, nil, nil) do
    &elem(&1, 1)[field]
  end

  defp sort_mapper(field, nil, field) do
    sort_mapper(field, nil, nil)
  end

  defp sort_mapper(field, nil, secondary) do
    &{elem(&1, 1)[field], elem(&1, 1)[secondary]}
  end

  defp sort_mapper(_, mapper, _) do
    mapper
  end

  @doc """
  Get the server's timezone offset in seconds.
  """
  @spec timezone_offset() :: integer
  def timezone_offset do
    NaiveDateTime.diff(NaiveDateTime.from_erl!(:calendar.local_time()), NaiveDateTime.utc_now())
  end
end
