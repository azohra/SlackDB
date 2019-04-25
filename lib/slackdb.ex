defmodule SlackDB do
  @moduledoc """
  GenServer that is responsible for all interactions with SlackDB.

  On startup, the server will load into memory the current state of the
  server (as described in the supervisor channel). All changes to state
  (channel additions and archivals) made through this API will be updated
  and persisted in the supervisor channel
  """
  use GenServer
  use Private
  require Logger
  alias SlackDB.Client

  @typedoc """
  Types of SlackDB keys represented as atoms

  Types
    * `:voting` - replies to keys are treated as a ballot where reactions represent support for that particular value. winner takes all.
    * `:multiple` - the reply thread represents an array that is returned in full and in chronological order
    * `:single_front` - the first reply to the key is the value
    * `:single_back` - the most recent reply to the key is the value
  """
  @type key_type :: :voting | :multiple | :single_front | :single_back
  @typedoc """
  More key metadata options represented as atoms

  Types
    * `:constant` - key cannot changed after creation (save for deletion)
    * `:undeletable` - key cannot be deleted (through this API)
  """
  @type more_metadata :: :constant | :undeletable
  @typedoc """
  Represents the types of values that keys can hold. Since all values are stored in Slack,
  they are all returned as strings (or a list of strings in the case of key_type `:multiple`)
  """
  @type value :: String.t() | list(String.t())

  @emoji_to_metadata %{
    ":thumbsup:" => :voting,
    ":family:" => :multiple,
    ":hear_no_evil:" => :single_front,
    ":monkey:" => :single_back,
    ":do_not_litter:" => :constant,
    # ":octagonal_sign:" => :blocked,
    ":anchor:" => :undeletable
  }

  @metadata_to_emoji %{
    voting: ":thumbsup:",
    multiple: ":family:",
    single_front: ":hear_no_evil:",
    single_back: ":monkey:",
    constant: ":do_not_litter:",
    # blocked: ":octagonal_sign:",
    undeletable: ":anchor:"
  }

  @key_type_regex ":thumbsup:|:family:|:hear_no_evil:|:monkey:"
  @key_schema ~r/(?<key_phrase>.+)\s(?<key_type>#{@key_type_regex})(?<more_metadata>.*)/

  ####################################################################################
  ## PUBLIC API ######################################################################
  ####################################################################################

  @doc """
  Start genserver, pull server config from application environment and pass to init/1
  """
  def start_link do
    config = Application.get_env(:slackdb, :servers)

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Create a key/value pair in the specified server and channel of the given type

  This essentially overwrites the key if it already exist. It posts a new message that will always be prioritized by `read/4` because it is more recent.

  The value passed in may be either a String or a list of Strings that will be posted in the key's thread, in order.
  You can specify additional metadata to be added to the key using an optional list.

  This function returns an error tuple or a list of tuples indicating the result of posting each value.
  The channel that is specified must exist in the scope of the server.

  ## Example

      iex> SlackDB.create("dog_shelter", "adopted", "Beagles", ["Buddy", "Rufus"], :multiple, [:undeletable])
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129093.001000"
        }
      ]
  """
  @spec create(
          String.t(),
          String.t(),
          String.t(),
          value(),
          key_type(),
          list(more_metadata())
        ) :: {:error, String.t()} | list(tuple())
  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata \\ [])

  def create(server_name, channel_name, key_phrase, value, key_type, add_metadata)
      when is_binary(value) and is_list(add_metadata) and is_atom(key_type),
      do: create(server_name, channel_name, key_phrase, [value], key_type, add_metadata)

  def create(server_name, channel_name, key_phrase, values, key_type, add_metadata)
      when is_list(values) and is_list(add_metadata) and is_atom(key_type) do
    Regex.named_captures(@key_schema, key_phrase)
    |> case do
      nil ->
        GenServer.call(
          __MODULE__,
          {:create, server_name, channel_name, key_phrase, values, [key_type | add_metadata]}
        )

      _ ->
        {:error, "invalid_key_phrase"}
    end
  end

  @doc """
  Reads a key in the given server and channel, raising an error if anything went wrong

  This will always pull from the most recently posted message that matches the key schema.

  Setting `only_bot?` to true will search only for keys posted under the bot name specified in the config.

  ## Example

      iex> SlackDB.read!("dog_shelter", "adopted", "Beagles")
      ["Buddy", "Rufus"]
  """
  @spec read!(String.t(), String.t(), String.t(), boolean()) :: value()
  def read!(server_name, channel_name, key_phrase, only_bot? \\ true) do
    read(server_name, channel_name, key_phrase, only_bot?)
    |> case do
      {:ok, val} -> val
      {:error, msg} -> raise msg
    end
  end

  @doc """
  Reads a key in the given server and channel

  This will always pull from the most recently posted message that matches the key schema.

  Setting `only_bot?` to true will search only for keys posted under the bot name specified in the config.

  ## Example

      iex> SlackDB.read("dog_shelter", "adopted", "Beagles")
      {:ok, ["Buddy", "Rufus"]}
  """
  @spec read(String.t(), String.t(), String.t(), boolean()) ::
          {:error, String.t()} | {:ok, value()}
  def read(server_name, channel_name, key_phrase, only_bot? \\ true) do
    with {:ok, key} <- search(server_name, channel_name, key_phrase, only_bot?) do
      # IO.inspect(key)
      get_value(key)
    else
      err -> err
    end
  end

  @doc """
  Overwrites the current value of the key by deleting the current thread and posting new values (sacrificing rollback)

  This is the only way to change the value of a `:single_front` key.

  This function returns an error tuple or a list of tuples indicating the result of posting each value.

  ## Example

      iex> SlackDB.update("dog_shelter", "adopted", "Chihuahuas", "Ren")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]
  """
  @spec update(String.t(), String.t(), String.t(), value()) ::
          {:error, String.t()} | list(tuple())
  def update(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: update(server_name, channel_name, key_phrase, [value])

  def update(server_name, channel_name, key_phrase, values) when is_list(values) do
    with %{bot_token: bot_token, user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- search(server_name, channel_name, key_phrase, false) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_update_constant_key"}

        true ->
          wipe_thread(user_token, key, false)
          post_thread(bot_token, key.channel_id, values, key.ts)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Deletes a key and it's associated thread

  Beware of rate_limiting issues discussed in the README

  This function returns an error tuple or a list of tuples indicating the result of deleting each message in the thread.

  ## Example

      iex> SlackDB.delete("dog_shelter", "yet-to-be-adopted", "Chihuahuas")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        },
      ]
  """
  @spec delete(String.t(), String.t(), String.t()) :: {:error, String.t()} | list(tuple())
  def delete(server_name, channel_name, key_phrase) do
    with %{user_token: user_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- search(server_name, channel_name, key_phrase, false) do
      cond do
        :undeletable in key.metadata -> {:error, "cannot_delete_undeletable_key"}
        true -> wipe_thread(user_token, key, true)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Appends values to the current thread of the key (maintaining history)

  You can use this to append to the list of keys with type `:multiple`.
  Or to add voting options to `:voting` keys.
  Or to change the value of `:single_back` keys

  This function returns an error tuple or a list of tuples indicating the result of posting each value.

  ## Example

      iex> SlackDB.append("dog_shelter", "adopted", "Chihuahuas", "Ren")
      [
        ok: %{
          "channel" => "CHU427918",
          "message" => %{...},
          "ok" => true,
          "ts" => "1556129092.000800"
        }
      ]
  """
  @spec append(String.t(), String.t(), String.t(), value()) ::
          {:error, String.t()} | list(tuple())
  def append(server_name, channel_name, key_phrase, value) when is_binary(value),
    do: append(server_name, channel_name, key_phrase, [value])

  def append(server_name, channel_name, key_phrase, values) when is_list(values) do
    with %{bot_token: bot_token} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, key} <- search(server_name, channel_name, key_phrase, true) do
      cond do
        :constant in key.metadata ->
          {:error, "cannot_append_to_constant_key"}

        true ->
          post_thread(bot_token, key.channel_id, values, key.ts)
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Creates a new channel and updates the current state of the database

  A channel must exist in the current state of the databse to create keys or to invite users.
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is created.

  ## Example

      iex> SlackDB.new_channel("dog_shelter", "volunteers", false)
      {:ok, "channel added"}
  """
  @spec new_channel(String.t(), String.t(), boolean()) :: {:error, String.t()} | {:ok, map()}
  def new_channel(server_name, channel_name, is_private?) do
    with %{user_token: user_token, supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, %{"name" => channel_name, "id" => channel_id}} <-
           Client.conversations_create(user_token, channel_name, is_private?),
         {:ok, new_state} <-
           GenServer.call(__MODULE__, {:put_channel, server_name, channel_name, channel_id}),
         [{:ok, _resp}] <-
           append(
             server_name,
             supervisor_channel_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Includes an existing channel and updates the state of the database

  A channel must exist in the current state of the databse to create keys or to invite users
  Since bots cannot add themselves to channels, you must also add the bot manually once the channel is included.

  ## Example

      iex> SlackDB.include_channel("dog_shelter", "employees")
      {:ok, "channel added"}
  """
  @spec include_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def include_channel(server_name, channel_name) do
    with %{user_token: user_token, supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, resp} <- Client.conversations_list(user_token),
         convo_list <- convo_cursor_pagination(user_token, [], resp) do
      case convo_list |> Enum.find(fn chnl -> chnl["name"] == channel_name end) do
        nil ->
          {:error, "channel_not_found"}

        %{"id" => channel_id} ->
          with {:ok, new_state} <-
                 GenServer.call(__MODULE__, {:put_channel, server_name, channel_name, channel_id}),
               [{:ok, _resp}] <-
                 append(
                   server_name,
                   supervisor_channel_name,
                   server_name,
                   new_state |> get_in([server_name, :channels]) |> Jason.encode!()
                 ) do
            {:ok, new_state}
          else
            err -> err
          end
      end
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Archives a channel and removes it from the state of the database

  ## Example

      iex> SlackDB.archive_channel("dog_shelter", "coops-winter-2019")
      {:ok, "channel archived"}
  """
  @spec archive_channel(String.t(), String.t()) :: {:error, String.t()} | {:ok, map()}
  def archive_channel(server_name, channel_name) do
    with %{supervisor_channel_name: supervisor_channel_name} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name),
         {:ok, _resp} <- GenServer.call(__MODULE__, {:archive, server_name, channel_name}),
         new_state <- GenServer.call(__MODULE__, {:dump}),
         [{:ok, _resp}] <-
           append(
             server_name,
             supervisor_channel_name,
             server_name,
             new_state |> get_in([server_name, :channels]) |> Jason.encode!()
           ) do
      {:ok, new_state}
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Invites a user_id or a list of user_ids to a specified channel

  ## Example

      iex> SlackDB.invite_to_channel("dog_shelter", "adopted", ["USERID1", "USERID2"])
      {:ok, %{"name" => "adopted", "id" => "CHU427918"}}
  """
  @spec invite_to_channel(String.t(), String.t(), String.t() | list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_to_channel(server_name, channel_name, user_id) when is_binary(user_id),
    do: invite_to_channel(server_name, channel_name, [user_id])

  def invite_to_channel(server_name, channel_name, user_ids)
      when is_list(user_ids) and length(user_ids) < 30 and length(user_ids) > 0 do
    GenServer.call(__MODULE__, {:invite, server_name, channel_name, user_ids})
  end

  @doc """
  Invites a user_id or a list of user_ids to the supervisor channel of a specified server

  ## Example

      iex> SlackDB.invite_supervisors("dog_shelter", ["USERID1", "USERID2"])
      {:ok, %{"name" => "adopted", "id" => "CHU427918"}}
  """
  @spec invite_supervisors(String.t(), String.t() | list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_supervisors(server_name, user_id) when is_binary(user_id),
    do: invite_supervisors(server_name, [user_id])

  def invite_supervisors(server_name, user_ids)
      when is_list(user_ids) and length(user_ids) < 30 and length(user_ids) > 0 do
    with %{user_token: user_token, supervisor_channel_id: supervisor_channel_id} <-
           Application.get_env(:slackdb, :servers) |> Map.get(server_name) do
      Client.conversations_invite(
        user_token,
        supervisor_channel_id,
        Enum.join(user_ids, ",")
      )
    else
      nil -> {:error, "server_not_found_in_config"}
      %{} -> {:error, "improper_config"}
      err -> err
    end
  end

  @doc """
  Returns a map representing the current state of the database

  ## Example

      iex> SlackDB.dump()
      %{
        "dog_shelter" => %{
          bot_name: "Jeanie",
          bot_token: "xoxb-shhh...",
          user_token: "xoxp-shhh..."
          channels: %{
            "adopted" => "CHU427918",
            "yet-to-be-adopted" => "CJ57Z7QS1"
          },
          supervisor_channel_id: "CFC6MRQ06",
          supervisor_channel_name: "slackdb-admin",
        }
      }
  """
  @spec dump() :: map()
  def dump() do
    GenServer.call(__MODULE__, {:dump})
  end

  ####################################################################################
  ## GENSERVER CALLBACKS #############################################################
  ####################################################################################
  @impl true
  def init(config) do
    servers = Map.keys(config)

    server_states =
      servers
      |> Enum.map(fn server_name ->
        {server_name,
         read(
           server_name,
           get_in(config, [server_name, :supervisor_channel_name]),
           server_name
         )}
      end)
      |> Enum.map(&initialize_supervisor_channel/1)

    config =
      config
      |> populate_channels(server_states)

    # |> IO.inspect()

    {:ok, config}
  end

  @impl true
  def handle_call(
        {:create, server_name, channel_name, key_phrase, values, all_metadata},
        _from,
        state
      )
      when is_list(values) do
    resp =
      with %{bot_token: bot_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            metadata_as_emojis =
              all_metadata |> Enum.map(fn x -> @metadata_to_emoji[x] end) |> Enum.join()

            with {:ok, %{"ts" => thread_ts}} <-
                   Client.chat_postMessage(
                     bot_token,
                     key_phrase <> " #{metadata_as_emojis}",
                     channel_id
                   ) do
              post_thread(bot_token, channel_id, values, thread_ts)
            else
              err -> err
            end
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    {:reply, resp, state}
  end

  def handle_call({:invite, server_name, channel_name, user_ids}, _from, state)
      when is_list(user_ids) do
    resp =
      with %{user_token: user_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            Client.conversations_invite(user_token, channel_id, Enum.join(user_ids, ","))
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    {:reply, resp, state}
  end

  def handle_call({:put_channel, server_name, channel_name, channel_id}, _from, state) do
    new_state = state |> put_kv_in([server_name, :channels], channel_name, channel_id)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:archive, server_name, channel_name}, _from, state) do
    resp =
      with %{user_token: user_token, channels: channels} <- state[server_name] do
        case channels[channel_name] do
          nil ->
            {:error, "channel_name_not_in_database"}

          channel_id ->
            Client.conversations_archive(user_token, channel_id)
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end

    new_state =
      case resp do
        {:ok, _} ->
          {_val, new} = state |> pop_in([server_name, :channels, channel_name])
          new

        {:error, _} ->
          state
      end

    {:reply, resp, new_state}
  end

  def handle_call({:dump}, _from, state), do: {:reply, state, state}

  ####################################################################################
  ## HELPERS #########################################################################
  ####################################################################################

  private do
    # required scopes: search:read
    # uses: search.messages with user_token
    @spec search(String.t(), String.t(), String.t(), boolean()) ::
            {:ok, SlackDB.Key.t()} | {:error, String.t()}
    defp search(server_name, channel_name, key_phrase, only_bot?)

    defp search(server_name, channel_name, key_phrase, true) do
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

    defp search(server_name, channel_name, key_phrase, false) do
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

    defp parse_matches(%{"matches" => matches, "total" => total}) do
      case total do
        0 -> {:error, "no_search_matches"}
        _number -> first_matched_schema(matches)
      end
    end

    # recurses through an array of search results, creating a %SlackDB.Key{} out of the first one that matches the key schema
    defp first_matched_schema([head]) do
      Regex.named_captures(@key_schema, head["text"])
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
               @emoji_to_metadata[key_type]
               | Regex.scan(~r/:[^:]+:/, more_metadata)
                 |> List.flatten()
                 |> Enum.map(fn x -> @emoji_to_metadata[x] end)
             ],
             channel_id: head["channel"]["id"],
             ts: head["ts"],
             channel_name: head["channel"]["name"]
           }}
      end
    end

    defp first_matched_schema([head | tail]) do
      Regex.named_captures(@key_schema, head["text"])
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
               @emoji_to_metadata[key_type]
               | Regex.scan(~r/:[^:]+:/, more_metadata)
                 |> List.flatten()
                 |> Enum.map(fn x -> @emoji_to_metadata[x] end)
             ],
             channel_id: head["channel"]["id"],
             ts: head["ts"],
             channel_name: head["channel"]["name"]
           }}
      end
    end

    # required scopes: channels:history, groups:history
    # uses: conversations.replies
    @spec get_value(SlackDB.Key.t()) :: {:error, String.t()} | {:ok, value}
    defp get_value(
           %SlackDB.Key{server_name: server_name, metadata: [:single_front | _more_metadata]} =
             key
         ) do
      with %{user_token: user_token} <-
             Application.get_env(:slackdb, :servers) |> Map.get(server_name),
           {:ok, resp} <- Client.conversations_replies(user_token, key) do
        case replies_cursor_pagination(user_token, key, [], resp) do
          li when is_list(li) and length(li) > 0 -> {:ok, List.first(li)["text"]}
          li when is_list(li) and length(li) == 0 -> {:error, "no_replies"}
          _ -> {:error, "error_pulling_thread"}
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end
    end

    defp get_value(
           %SlackDB.Key{server_name: server_name, metadata: [:single_back | _more_metadata]} = key
         ) do
      with %{user_token: user_token} <-
             Application.get_env(:slackdb, :servers) |> Map.get(server_name),
           {:ok, %{"messages" => [_key_message | replies]}} <-
             Client.conversations_replies(user_token, key, nil, 1) do
        case replies do
          [] -> {:error, "no_replies"}
          [%{"text" => text}] -> {:ok, text}
          _ -> {:error, "unexpected_reply_format"}
        end
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end
    end

    defp get_value(
           %SlackDB.Key{server_name: server_name, metadata: [:multiple | _more_metadata]} = key
         ) do
      with %{user_token: user_token} <-
             Application.get_env(:slackdb, :servers) |> Map.get(server_name),
           {:ok, resp} <- Client.conversations_replies(user_token, key) do
        {:ok,
         replies_cursor_pagination(user_token, key, [], resp)
         |> Enum.map(fn msg -> msg["text"] end)}
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end
    end

    defp get_value(
           %SlackDB.Key{
             server_name: server_name,
             # channel_id: channel_id,
             metadata: [:voting | _more_metadata]
           } = key
         ) do
      with %{user_token: user_token} <-
             Application.get_env(:slackdb, :servers) |> Map.get(server_name),
           {:ok, resp} <- Client.conversations_replies(user_token, key) do
        {:ok,
         replies_cursor_pagination(user_token, key, [], resp)
         |> Enum.max_by(&tally_reactions/1)
         |> Map.get("text")}
      else
        nil -> {:error, "server_not_found_in_config"}
        %{} -> {:error, "improper_config"}
        err -> err
      end
    end

    # paginate through conversations.replies responeses and collect all replies to a key in a list, chronologically
    defp replies_cursor_pagination(_user_token, _key, array, %{"has_more" => false} = response) do
      [_key_message | replies] = response["messages"]
      replies ++ array
    end

    defp replies_cursor_pagination(
           user_token,
           key,
           array,
           %{"has_more" => true, "response_metadata" => %{"next_cursor" => cursor}} = response
         ) do
      [_key_message | replies] = response["messages"]

      with {:ok, next_response} <- Client.conversations_replies(user_token, key, cursor) do
        replies_cursor_pagination(
          user_token,
          key,
          replies ++ array,
          next_response
        )
      end
    end

    # paginate through conversations.list responeses and collect public+private channels in a list
    defp convo_cursor_pagination(
           _user_token,
           array,
           %{"channels" => channels, "response_metadata" => %{"next_cursor" => ""}}
         ) do
      channels ++ array
    end

    defp convo_cursor_pagination(
           user_token,
           array,
           %{"channels" => channels, "response_metadata" => %{"next_cursor" => cursor}}
         ) do
      with {:ok, next_response} <- Client.conversations_list(user_token, cursor) do
        convo_cursor_pagination(
          user_token,
          channels ++ array,
          next_response
        )
      end
    end

    defp post_thread(bot_token, channel_id, text, thread_ts) when is_binary(text),
      do: post_thread(bot_token, channel_id, [text], thread_ts)

    defp post_thread(bot_token, channel_id, [last_text], thread_ts),
      do: [Client.chat_postMessage(bot_token, last_text, channel_id, thread_ts)]

    defp post_thread(bot_token, channel_id, [first_text | more_posts], thread_ts) do
      [
        Client.chat_postMessage(bot_token, first_text, channel_id, thread_ts)
        | post_thread(bot_token, channel_id, more_posts, thread_ts)
      ]
    end

    # receives result from reactions.get call and outputs total reactions on the given message

    defp tally_reactions(message_details) do
      case message_details["reactions"] do
        nil ->
          0

        reactions_list when is_list(reactions_list) ->
          Enum.reduce(reactions_list, 0, fn react, acc -> react["count"] + acc end)
      end
    end

    # like Kernel.put_in but it can add a k/v pair to an existing nested map rather than only update the value
    defp put_kv_in(map, [], new_key, new_value),
      do: Map.put(map, new_key, new_value)

    defp put_kv_in(map, [head | tail], new_key, new_value) do
      Map.put(map, head, put_kv_in(map[head], tail, new_key, new_value))
    end

    defp populate_channels(map, [{server_name, state}]) do
      put_kv_in(map, [server_name], :channels, state)
    end

    defp populate_channels(map, [{server_name, state} | more_server_states]) do
      put_kv_in(populate_channels(map, more_server_states), [server_name], :channels, state)
    end

    defp initialize_supervisor_channel({server_name, {:ok, server_state}}) do
      case server_state |> Jason.decode() do
        {:ok, map} -> {server_name, map}
        other -> {server_name, other}
      end
    end

    defp initialize_supervisor_channel({server_name, {:error, _error_message}}) do
      init =
        with %{bot_token: bot_token, supervisor_channel_id: channel_id} <-
               Application.get_env(:slackdb, :servers) |> Map.get(server_name),
             {:ok, %{"ts" => thread_ts}} <-
               Client.chat_postMessage(
                 bot_token,
                 server_name <> " #{@metadata_to_emoji[:single_back]}",
                 channel_id
               ),
             _resp_list <- post_thread(bot_token, channel_id, "{}", thread_ts) do
          %{}
        else
          nil -> {:error, "server_not_found_in_config"}
          %{} -> {:error, "improper_config"}
          err -> err
        end

      {server_name, init}
    end

    defp wipe_thread(user_token, key, include_key?) do
      with {:ok, resp} <- Client.conversations_replies(user_token, key) do
        case include_key? do
          false -> replies_cursor_pagination(user_token, key, [], resp)
          true -> replies_cursor_pagination(user_token, key, [%{"ts" => key.ts}], resp)
        end
        |> Flow.from_enumerable()
        |> Flow.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
        |> Enum.to_list()

        # |> Enum.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
      else
        err -> err
      end
    end
  end
end
