package in.marketbrain.paper;

import java.util.Arrays;

/** Process-owned secret only. No persistence, database permission change or authentication claim. */
public final class PaperRuntimeCredential implements PaperWriterConnector.SecretSource, AutoCloseable {
    public static final class Locked extends RuntimeException {
        public Locked() { super("Paper review is locked"); }
    }
    private char[] secret;
    private boolean closed;

    public synchronized boolean ready() { return !closed && secret != null; }

    /** The caller owns/erases input. Never replace an existing credential implicitly. */
    public synchronized void unlock(byte[] input) {
        if (closed) throw new Locked();
        if (input == null || input.length != 64) throw new IllegalArgumentException("Invalid runtime credential");
        for (byte b : input) if (!(b >= '0' && b <= '9' || b >= 'a' && b <= 'f'))
            throw new IllegalArgumentException("Invalid runtime credential");
        if (secret != null) {
            int difference = 0;
            for (int i = 0; i < 64; i++) difference |= secret[i] ^ input[i];
            if (difference != 0) throw new IllegalStateException("Lock before replacing runtime credential");
            return;
        }
        secret = new char[64];
        for (int i = 0; i < 64; i++) secret[i] = (char)input[i];
    }
    @Override public synchronized char[] read() {
        if (!ready()) throw new Locked();
        return secret.clone();
    }
    public synchronized void lock() {
        if (secret != null) Arrays.fill(secret, '\0');
        secret = null;
    }
    @Override public synchronized void close() { lock(); closed = true; }
}
