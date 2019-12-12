defmodule SlackDB.Server do
  @moduledoc false

  use GenServer
  use Private

  alias SlackDB.Utils
  alias SlackDB.Client
  alias SlackDB.Utils
  alias SlackDB.Messages

  @doc """
  Start genserver, pull server config from application environment and pass to init/1
  """
  def start_link do
    config = Application.get_env(:slackdb, :servers)

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
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
         SlackDB.read(
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
              all_metadata |> Enum.map(fn x -> Utils.metadata_to_emoji(x) end) |> Enum.join()

            with {:ok, %{"ts" => thread_ts}} <-
                   Client.chat_postMessage(
                     bot_token,
                     key_phrase <> " #{metadata_as_emojis}",
                     channel_id
                   ) do
              Messages.post_thread(bot_token, channel_id, thread_ts, values)
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
    new_state = state |> put_in([server_name, :channels, channel_name], channel_id)
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
  ## INIT HELPERS ####################################################################
  ####################################################################################

  private do
    defp populate_channels(map, [{server_name, state}]) do
      put_in(map, [server_name, :channels], state)
    end

    defp populate_channels(map, [{server_name, state} | more_server_states]) do
      populate_channels(map, more_server_states)
      |> put_in([server_name, :channels], state)
    end

    defp initialize_supervisor_channel({server_name, {:ok, server_state}}) do
      case server_state |> Jason.decode() do
        {:ok, map} -> {server_name, map}
        other -> {server_name, other}
      end
    end

    defp initialize_supervisor_channel({server_name, {:error, _error_message}}) do
      init =
        with [bot_token, sprvsr_chnl_id] <-
               Utils.get_tokens(server_name, [:bot_token, :supervisor_channel_id]),
             {:ok, %{"ts" => thread_ts}} <-
               Client.chat_postMessage(
                 bot_token,
                 server_name <> " #{Utils.metadata_to_emoji(:single_back)}",
                 sprvsr_chnl_id
               ),
             _resp_list <- Messages.post_thread(bot_token, sprvsr_chnl_id, thread_ts, "{}") do
          %{}
        else
          nil -> {:error, "server_not_found_in_config"}
          %{} -> {:error, "improper_config"}
          err -> err
        end

      {server_name, init}
    end
  end
end
