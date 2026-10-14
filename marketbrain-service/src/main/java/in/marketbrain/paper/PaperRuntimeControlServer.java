package in.marketbrain.paper;

import java.io.IOException;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;

/** Local OS-user authority, not an HTTP endpoint. Only socket metadata is stored, never password bytes. */
public final class PaperRuntimeControlServer implements AutoCloseable {
    private final PaperRuntimeCredential credential;
    private final Path socket;
    private final ServerSocketChannel listener;
    private final Object socketKey;
    private final Thread worker;
    private volatile boolean closed;
    private volatile SocketChannel active;

    public PaperRuntimeControlServer(PaperRuntimeCredential credential, Path directory) throws IOException {
        this.credential = java.util.Objects.requireNonNull(credential);
        requirePrivateDirectory(directory);
        socket = directory.resolve("control.sock");
        // A stale socket requires reviewed operator recovery. Never delete an unknown path at startup.
        if (Files.exists(socket, LinkOption.NOFOLLOW_LINKS)) throw new IOException("Control socket already exists");
        listener = ServerSocketChannel.open(StandardProtocolFamily.UNIX);
        try {
            listener.bind(UnixDomainSocketAddress.of(socket));
            Files.setPosixFilePermissions(socket, PosixFilePermissions.fromString("rw-------"));
            socketKey = Files.readAttributes(socket, java.nio.file.attribute.BasicFileAttributes.class,
                    LinkOption.NOFOLLOW_LINKS).fileKey();
            listener.configureBlocking(false);
        } catch (Exception failure) {
            try { listener.close(); } finally { credential.close(); }
            throw new IOException("Cannot initialize private review control");
        }
        worker = new Thread(this::serve, "paper-runtime-control");
        worker.setDaemon(true); worker.start();
    }
    static void requirePrivateDirectory(Path directory) throws IOException {
        if (!directory.isAbsolute() || !directory.normalize().equals(directory)) throw new IOException("Invalid control directory");
        for (Path p = directory; p != null; p = p.getParent())
            if (Files.isSymbolicLink(p)) throw new IOException("Control links forbidden");
        if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)
                || !Files.getPosixFilePermissions(directory).equals(PosixFilePermissions.fromString("rwx------"))
                || !Files.getOwner(directory).getName().equals(System.getProperty("user.name")))
            throw new IOException("Private current-user control directory required");
    }
    private void serve() {
        try {
            while (!closed) {
                SocketChannel channel = listener.accept();
                if (channel == null) { Thread.sleep(10); continue; }
                active = channel;
                try (channel) {
                    channel.configureBlocking(false);
                    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
                    byte[] frame = null;
                    try {
                        frame = PaperRuntimeControl.receive(channel, 71, deadline);
                        String response = apply(frame);
                        PaperRuntimeControl.send(channel, response.getBytes(StandardCharsets.US_ASCII), deadline);
                    } finally { if (frame != null) Arrays.fill(frame, (byte)0); }
                } catch (Exception refused) { /* Bounded malformed/abandoned request. Never log bytes or provider errors. */ }
                finally { active = null; }
            }
        } catch (Exception stopped) {
            credential.lock(); // A failed control listener must not leave a ready secret behind.
            if (stopped instanceof InterruptedException) Thread.currentThread().interrupt();
        }
    }
    private String apply(byte[] frame) {
        if (Arrays.equals(frame, "STATUS".getBytes(StandardCharsets.US_ASCII)))
            return credential.ready() ? "UNLOCKED" : "LOCKED";
        if (Arrays.equals(frame, "LOCK".getBytes(StandardCharsets.US_ASCII))) { credential.lock(); return "LOCKED"; }
        if (frame.length == 71 && Arrays.equals(Arrays.copyOf(frame, 7), "UNLOCK ".getBytes(StandardCharsets.US_ASCII))) {
            byte[] secret = Arrays.copyOfRange(frame, 7, 71);
            try { credential.unlock(secret); return "UNLOCKED"; }
            catch (RuntimeException refused) { return "REFUSED"; }
            finally { Arrays.fill(secret, (byte)0); }
        }
        return "REFUSED";
    }
    @Override public void close() throws IOException {
        closed = true;
        try {
            listener.close();
            SocketChannel connection = active;
            if (connection != null) connection.close();
        } finally {
            worker.interrupt();
            try { worker.join(4000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            credential.close();
        }
        if (Files.exists(socket, LinkOption.NOFOLLOW_LINKS) && socketKey != null
                && socketKey.equals(Files.readAttributes(socket, java.nio.file.attribute.BasicFileAttributes.class,
                    LinkOption.NOFOLLOW_LINKS).fileKey())) Files.delete(socket);
    }
}
