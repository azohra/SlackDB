defmodule SlackDB.Search do
  use Private

  alias SlackDB.Client
  alias SlackDB.Utils

  @emoji_list_regex ~r/:[^:]+:/

  @spec search(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, SlackDB.Key.t()} | {:error, String.t()}
  def search(server_name, channel_name, key_phrase, only_bot?)

  def search(server_name, channel_name, key_phrase, true) do
    with %{user_token: user_token, bot_name: bot_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, match_info} <-
           Client.search_messages(
             user_token,
             "in:##{channel_name} from:#{bot_name} \"#{key_phrase}\""
           ),
         {:ok, key} <- parse_matches(match_info) do
      {:ok, key |> Map.put(:server_name, server_name)}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  def search(server_name, channel_name, key_phrase, false) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, match_info} <-
           Client.search_messages(user_token, "in:##{channel_name} \"#{key_phrase}\""),
         {:ok, key} <- parse_matches(match_info) do
      {:ok, key |> Map.put(:server_name, server_name)}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  private do
    defp parse_matches(%{"matches" => matches, "total" => total}) do
      case total do
        0 -> {:error, "no_search_matches"}
        _number -> first_matched_schema(matches)
      end
    end

    # recurses through an array of search results, creating a %SlackDB.Key{} out of the first one that matches the key schema
    defp first_matched_schema([head]) do
      Utils.check_schema(head["text"])
      |> case do
        nil ->
          {:error, "no_search_result_matching_key_schema"}

        %{
          "key_phrase" => key_phrase,
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
      end
    end

    defp first_matched_schema([head | tail]) do
      Utils.check_schema(head["text"])
      |> case do
        nil ->
          first_matched_schema(tail)

        %{
          "key_phrase" => key_phrase,
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
      end
    end
  end
end
