using Gdk;
using Gee;

using Xmpp;
using Dino.Entities;

namespace Dino {

public interface JingleFileEncryptionHelper : Object {
    public abstract bool can_transfer(Conversation conversation);
    public abstract async bool can_encrypt(Conversation conversation, FileTransfer file_transfer, Jid? full_jid = null);
    public abstract string? get_precondition_name(Conversation conversation, FileTransfer file_transfer);
    public abstract Object? get_precondition_options(Conversation conversation, FileTransfer file_transfer);
    public abstract Encryption get_encryption(Xmpp.Xep.JingleFileTransfer.FileTransfer jingle_transfer);
}

public class JingleFileEncryptionHelperTransferOnly : JingleFileEncryptionHelper, Object  {
    public bool can_transfer(Conversation conversation) {
        return true;
    }
    public async bool can_encrypt(Conversation conversation, FileTransfer file_transfer, Jid? full_jid) {
        return false;
    }
    public string? get_precondition_name(Conversation conversation, FileTransfer file_transfer) {
        return null;
    }
    public Object? get_precondition_options(Conversation conversation, FileTransfer file_transfer) {
        return null;
    }
    public Encryption get_encryption(Xmpp.Xep.JingleFileTransfer.FileTransfer jingle_transfer) {
        return Encryption.NONE;
    }
}

public class JingleFileHelperRegistry {
    private static JingleFileHelperRegistry INSTANCE;
    public static JingleFileHelperRegistry instance { get {
        if (INSTANCE == null) {
            INSTANCE = new JingleFileHelperRegistry();
            INSTANCE.add_encryption_helper(Encryption.NONE, new JingleFileEncryptionHelperTransferOnly());
        }
        return INSTANCE;
    } }

    internal HashMap<Encryption, JingleFileEncryptionHelper> encryption_helpers = new HashMap<Encryption, JingleFileEncryptionHelper>();

    public void add_encryption_helper(Encryption encryption, JingleFileEncryptionHelper helper) {
        encryption_helpers[encryption] = helper;
    }

    public JingleFileEncryptionHelper? get_encryption_helper(Encryption encryption) {
        if (encryption_helpers.has_key(encryption)) {
            return encryption_helpers[encryption];
        }
        return null;
    }
}

public class JingleFileProvider : FileProvider, Object {

    private StreamInteractor stream_interactor;
    private HashMap<string, Xmpp.Xep.JingleFileTransfer.FileTransfer> file_transfers = new HashMap<string, Xmpp.Xep.JingleFileTransfer.FileTransfer>();

    public JingleFileProvider(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        stream_interactor.account_added.connect(on_account_added);
    }

    public FileMeta get_file_meta(FileTransfer file_transfer) throws FileReceiveError {
        var file_meta = new FileMeta();
        file_meta.file_name = file_transfer.file_name;
        file_meta.size = file_transfer.size;
        return file_meta;
    }

    public FileReceiveData? get_file_receive_data(FileTransfer file_transfer) {
        return new FileReceiveData();
    }

    public async FileMeta get_meta_info(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws FileReceiveError {
        return file_meta;
    }

    public Encryption get_encryption(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) {
        Xmpp.Xep.JingleFileTransfer.FileTransfer? jingle_file_transfer = file_transfers[file_transfer.info];
        if (jingle_file_transfer == null) {
            warning("Could not determine jingle encryption - transfer data not available anymore");
            return Encryption.NONE;
        }
        foreach (JingleFileEncryptionHelper helper in JingleFileHelperRegistry.instance.encryption_helpers.values) {
            var encryption = helper.get_encryption(jingle_file_transfer);
            if (encryption != Encryption.NONE) return encryption;
        }
        return Encryption.NONE;
    }

    public async InputStream download(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws IOError {
        // TODO(hrxi) What should happen if `stream == null`?
        XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        Xmpp.Xep.JingleFileTransfer.FileTransfer? jingle_file_transfer = file_transfers[file_transfer.info];
        if (jingle_file_transfer == null) {
            throw new IOError.FAILED("Transfer data not available anymore");
        }
        yield jingle_file_transfer.accept(stream);
        return new LimitInputStream(jingle_file_transfer.stream, file_meta.size);
    }

    public int get_id() {
        return 1;
    }

    private void on_account_added(Account account) {
        stream_interactor.module_manager.get_module(account, Xmpp.Xep.JingleFileTransfer.Module.IDENTITY).file_incoming.connect((stream, jingle_file_transfer) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation(jingle_file_transfer.peer.bare_jid, account);
            if (conversation == null) return;

            string id = random_uuid();
            file_transfers[id] = jingle_file_transfer;

            FileMeta file_meta = new FileMeta();
            file_meta.size = jingle_file_transfer.size;
            file_meta.file_name = jingle_file_transfer.file_name;

            var time = new DateTime.now_utc();
            var from = jingle_file_transfer.peer.bare_jid;

            file_incoming(id, from, time, time, conversation, new FileReceiveData(), file_meta);
        });
    }
}

public class JingleFileSender : FileSender, Object {

    private StreamInteractor stream_interactor;

    public JingleFileSender(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public async bool is_upload_available(Conversation conversation) {
        if (conversation.type_ != Conversation.Type.CHAT) return false;

        JingleFileEncryptionHelper? helper = JingleFileHelperRegistry.instance.get_encryption_helper(conversation.encryption);
        if (helper == null) return false;
        if (!helper.can_transfer(conversation)) return false;

        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream == null) return false;

        Gee.List<Jid>? resources = stream.get_flag(Presence.Flag.IDENTITY).get_resources(conversation.counterpart);
        if (resources == null) return false;

        foreach (Jid full_jid in resources) {
            if (yield stream.get_module(Xep.JingleFileTransfer.Module.IDENTITY).is_available(stream, full_jid)) {
                return true;
            }
        }
        return false;
    }

    public async long get_file_size_limit(Conversation conversation) {
        if (yield can_send_conv(conversation)) {
            return int.MAX;
        }
        return -1;
    }

    public async bool can_send(Conversation conversation, FileTransfer file_transfer) {
        return yield can_send_conv(conversation);
    }

    private async bool can_send_conv(Conversation conversation) {
        if (conversation.type_ != Conversation.Type.CHAT) return false;

        // No file specific restrictions apply to Jingle file transfers
        return yield is_upload_available(conversation);
    }

    public async bool can_encrypt(Conversation conversation, FileTransfer file_transfer) {
        JingleFileEncryptionHelper? helper = JingleFileHelperRegistry.instance.get_encryption_helper(file_transfer.encryption);
        if (helper == null) return false;
        return yield helper.can_encrypt(conversation, file_transfer);
    }

    public async FileSendData? prepare_send_file(Conversation conversation, FileTransfer file_transfer, FileMeta file_meta) throws FileSendError {
        if (file_meta is HttpFileMeta) {
            throw new FileSendError.UPLOAD_FAILED("Cannot upload http file meta over Jingle");
        }
        return new FileSendData();
    }

    public async void send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) throws FileSendError {
        XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) throw new FileSendError.UPLOAD_FAILED("No stream available");
        JingleFileEncryptionHelper? helper = JingleFileHelperRegistry.instance.get_encryption_helper(file_transfer.encryption);
        bool must_encrypt = helper != null && yield helper.can_encrypt(conversation, file_transfer);
        // TODO(hrxi): Prioritization of transports (and resources?).
        foreach (Jid full_jid in stream.get_flag(Presence.Flag.IDENTITY).get_resources(conversation.counterpart)) {
            if (full_jid.equals(stream.get_flag(Bind.Flag.IDENTITY).my_jid)) {
                continue;
            }
            if (!yield stream.get_module(Xep.JingleFileTransfer.Module.IDENTITY).is_available(stream, full_jid)) {
                continue;
            }
            if (must_encrypt && !yield helper.can_encrypt(conversation, file_transfer, full_jid)) {
                continue;
            }
            string? precondition_name = null;
            Object? precondition_options = null;
            if (must_encrypt) {
                precondition_name = helper.get_precondition_name(conversation, file_transfer);
                precondition_options = helper.get_precondition_options(conversation, file_transfer);
                if (precondition_name == null) {
                    throw new FileSendError.ENCRYPTION_FAILED("Should have created a precondition, but did not");
                }
            }
            try {
                yield stream.get_module(Xep.JingleFileTransfer.Module.IDENTITY).offer_file_stream(stream, full_jid, file_transfer.input_stream, file_transfer.server_file_name, file_meta.size, precondition_name, precondition_options);
            } catch (Error e) {
                throw new FileSendError.UPLOAD_FAILED(@"offer_file_stream failed: $(e.message)");
            }
            return;
        }
    }

    public int get_id() { return 1; }

    public float get_priority() { return 50; }
}

}
