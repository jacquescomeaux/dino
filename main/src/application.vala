using Dino.Entities;
using Dino.Ui;
using Xmpp;
using Gee;
using GLib;

public class Dino.Ui.Application : GLib.Application, Dino.Application {
    private const string[] KEY_COMBINATION_QUIT = {"<Ctrl>Q", null};
    private const string[] KEY_COMBINATION_ADD_CHAT = {"<Ctrl>T", null};
    private const string[] KEY_COMBINATION_ADD_CONFERENCE = {"<Ctrl>G", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS = {"<Ctrl>Tab", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS_REV = {"<Ctrl><Shift>Tab", null};

    public Database db { get; set; }
    public Dino.Entities.Settings settings { get; set; }
    public StreamInteractor stream_interactor { get; set; }
    public Plugins.Registry plugin_registry { get; set; default = new Plugins.Registry(); }
    public SearchPathGenerator? search_path_generator { get; set; }
    Plugins.VideoCallPlugin call_plugin;
    Plugins.VideoCallWidget own_video;

    internal static bool print_version = false;
    private const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, ref print_version, "Display version number", null },
        { null }
    };

    public Application() throws Error {
        Object(application_id: "im.dino.Dino", flags: ApplicationFlags.HANDLES_OPEN);
        init();
        Environment.set_application_name("Dino");

        startup.connect (on_startup);
        activate.connect (on_activate);
        shutdown.connect (on_shutdown);

    }

    private void on_startup () {
        print ("Startup\n");
        if (print_version) {
            print(@"Dino $(Dino.get_version())\n");
            Process.exit(0);
        }
    }

    private void on_activate () {
        print("Activate\n");

        this.call_plugin = Dino.Application.get_default().plugin_registry.video_call_plugin;
        this.own_video = call_plugin.create_widget(Plugins.WidgetType.GTK4);

        Jid testJid = new Jid("test@jacquescomeaux.xyz");
        Gee.List<Account> accounts = stream_interactor.get_accounts();

        ConversationManager convMan = stream_interactor.get_module(ConversationManager.IDENTITY);
        MessageProcessor messageProc = stream_interactor.get_module(MessageProcessor.IDENTITY);
        Calls calls = stream_interactor.get_module(Calls.IDENTITY);
        
        Conversation? conversation = convMan.get_conversation(testJid, accounts[0]);
        convMan.start_conversation(conversation);
        Message out_message = stream_interactor.get_module(MessageProcessor.IDENTITY).create_out_message("test", conversation);

        messageProc.message_sent.connect(_ => { print("It was sent!\n"); });
        messageProc.send_message(out_message, conversation);

        calls.call_incoming.connect((call, call_state, conv, video, multiparty) => {
          print("INCOMING CALL!!!\n");
          print(@"video is $(video), multiparty is $(multiparty)\n");
          print(@"video is $(video), multiparty is $(multiparty)\n");
          print(@"$(conv.id.to_string()), $(conv.type_.to_string()), $(conv.counterpart.bare_jid.to_string())\n");
          print(@"stream_interactor: \n");
          print(@"call_plugin: \n");
          print(@"call: \n");
          if (call_state.parent_muc != null) print(@"parent_muc: $(call_state.parent_muc.bare_jid.to_string())\n");
          if (call_state.invited_to_group_call != null) print(@"invited_to_group_call: $(call_state.invited_to_group_call.bare_jid.to_string())\n");
          print(@"accepted: $(call_state.accepted)\n");
          print(@"use_cim: $(call_state.use_cim)\n");
          if (call_state.cim_call_id != null) print(@"cim_call_id: $(call_state.cim_call_id)\n");
          if (call_state.cim_counterpart != null) print(@"cim_counterpart: $(call_state.cim_counterpart.bare_jid.to_string())\n");
          print(@"cim_message_type: $(call_state.cim_message_type)\n");
          print(@"group_call: \n");
          print(@"we_should_send_audio: $(call_state.we_should_send_audio)\n");
          print(@"we_should_send_video: $(call_state.we_should_send_video)\n");
          print(@"number of peers: $(call_state.peers.size)\n");
          foreach (PeerState peer_state in call_state.peers.values) {
              print(@"Peer: \n");
              print(@"stream_interactor: \n");
              print(@"call_state: \n");
              print(@"calls: \n");
              print(@"call: \n");
              print(@"jid: $(peer_state.jid.bare_jid)\n");
              print(@"session: \n");
              print(@"sid: $(peer_state.sid)\n");
              print(@"internal_id: $(peer_state.internal_id)\n");
              if (peer_state.audio_content_parameter != null) print(@"audio_content_parameter: \n");
              if (peer_state.video_content_parameter != null) print(@"video_content_parameter: \n");
              if (peer_state.audio_content != null) print(@"audio_content: \n");
              if (peer_state.video_content != null) print(@"video_content: \n");
              if (peer_state.audio_encryption != null) print(@"audio_encryption: \n");
              if (peer_state.video_encryption != null) print(@"video_encryption: \n");
              print(@"encryption_keys_same: $(peer_state.encryption_keys_same)\n");
              print(@"video_encryptions size: $(peer_state.video_encryptions.size)\n");
              print(@"audio_encryptions size: $(peer_state.audio_encryptions.size)\n");
              print(@"first_peer: $(peer_state.first_peer)\n");
              print(@"waiting_for_inbound_muji_connection: $(peer_state.waiting_for_inbound_muji_connection)\n");
              if (peer_state.group_call != null) print(@"group_call: \n");
              print(@"counterpart_sends_video: $(peer_state.counterpart_sends_video)\n");
              print(@"we_should_send_audio: $(peer_state.we_should_send_audio)\n");
              print(@"we_should_send_video: $(peer_state.we_should_send_video)\n");
          }

          call_state.terminated.connect((who_terminated, reason_name, reason_text) => {
              Conversation? thisConv = convMan.get_conversation(who_terminated.bare_jid, call.account, Conversation.Type.CHAT);
              string display_name =
                thisConv != null ? get_conversation_display_name(stream_interactor, thisConv, null) : who_terminated.bare_jid.to_string();
              print(@"Call was terminated by $(who_terminated)\n");
              release();
          });

          call_state.accept();

        });
        hold();
    }

    private void on_shutdown () {
        print ("Shutdown\n");
    }

    public void handle_uri(string jid, string query, Gee.Map<string, string> options) {
        switch (query) {
            case "join":
                //show_join_muc_dialog(null, jid);
                break;
            case "message":
                Gee.List<Account> accounts = stream_interactor.get_accounts();
                Jid parsed_jid = null;
                try {
                    parsed_jid = new Jid(jid);
                } catch (InvalidJidError ignored) {
                    // Ignored
                }
                if (accounts.size == 1 && parsed_jid != null) {
                    Conversation conversation = stream_interactor.get_module(ConversationManager.IDENTITY).create_conversation(parsed_jid, accounts[0], Conversation.Type.CHAT);
                    stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);
                }

                break;
        }
    }
}
