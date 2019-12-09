defmodule SlackDB.Search do
  @moduledoc false

  use Private

  alias SlackDB.Client
  alias SlackDB.Utils

  @emoji_list_regex ~r/:[^:]+:/

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)

  @spec search(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, SlackDB.Key.t()} | {:error, String.t()}
  def search(server_name, channel_name, key_phrase, only_bot? \\ true)

  def search(server_name, channel_name, key_phrase, true) do
    with %{bot_name: bot_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name) do
      search_query(
        server_name,
        channel_name,
        "in:##{channel_name} from:#{bot_name} \"#{key_phrase}\"",
        key_phrase
      )
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
    end
  end

  def search(server_name, channel_name, key_phrase, false) do
    search_query(
      server_name,
      channel_name,
      "in:##{channel_name} \"#{key_phrase}\"",
      key_phrase
    )
  end

  def search_query(server_name, channel_name, query, key_phrase) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <-
           pagination_search(
             user_token,
             channel_name,
             query,
             key_phrase
           ) do
      {:ok, key |> Map.put(:server_name, server_name)}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  defp pagination_search(user_token, channel_name, query, key_phrase, page \\ 1) do
    with {:ok, %{"matches" => matches, "pagination" => pagination}} <-
           client().search_messages(user_token, query, page: page) do
      case find_first_match(matches, key_phrase) do
        {:ok, key} ->
          {:ok, key}

        {:error, msg} ->
          if pagination["page"] < pagination["page_count"] do
            pagination_search(user_token, channel_name, query, key_phrase, page + 1)
          else
            {:error, msg}
          end
      end
    end
  end

  defp find_first_match([], _key_phrase) do
    {:error, "found_no_matches"}
  end

  defp find_first_match([head | tail], key_phrase) do
    case Utils.check_schema(head["text"]) do
      %{
        "key_phrase" => ^key_phrase,
        "key_type" => key_type,
        "more_metadata" => more_metadata
      } ->
        {:ok,
         %SlackDB.Key{
           key_phrase: key_phrase,
           metadata: [
             Utils.emoji_to_metadata(key_type)
             | Regex.scan(@emoji_list_regex, more_metadata)
               |> List.flatten()
               |> Enum.map(fn x -> Utils.emoji_to_metadata(x) end)
           ],
           channel_id: head["channel"]["id"],
           ts: head["ts"],
           channel_name: head["channel"]["name"]
         }}

      # either this message isn't a key or
      # it is a key and it's the incorrect phrase
      # we should continue to search
      _else ->
        find_first_match(tail, key_phrase)
    end
  end
end
