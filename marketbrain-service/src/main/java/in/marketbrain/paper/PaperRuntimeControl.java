package in.marketbrain.paper;

import java.io.IOException;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Standalone JDK-only docker-exec client. No credentials in command arguments, files or output. */
public final class PaperRuntimeControl {
    public static final Path DIRECTORY = Path.of("/run/marketbrain-writer");
    public static final Path SOCKET = DIRECTORY.resolve("control.sock");
    private PaperRuntimeControl() {}

    static void pause(long deadline) throws IOException {
        if (System.nanoTime() - deadline >= 0) throw new IOException("Control deadline exceeded");
        try { Thread.sleep(5); } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); throw new IOException("Control interrupted");
        }
    }
    static byte[] receive(SocketChannel channel, int maximum, long deadline) throws IOException {
        ByteBuffer buffer = ByteBuffer.allocate(maximum + 1);
        try {
            while (true) {
                int count = channel.read(buffer);
                if (buffer.position() > maximum) throw new IOException("Control frame too large");
                if (count < 0) return Arrays.copyOf(buffer.array(), buffer.position());
                pause(deadline);
            }
        } finally { Arrays.fill(buffer.array(), (byte)0); }
    }
    static void send(SocketChannel channel, byte[] bytes, long deadline) throws IOException {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        while (buffer.hasRemaining()) { channel.write(buffer); pause(deadline); }
        channel.shutdownOutput();
    }
    static String request(Path socket, String command, byte[] secret) throws IOException {
        if (!java.util.Set.of("STATUS", "LOCK", "UNLOCK").contains(command)
                || (command.equals("UNLOCK") ? secret == null || secret.length != 64 : secret != null))
            throw new IllegalArgumentException("Invalid control request");
        byte[] frame = new byte[command.equals("UNLOCK") ? 71 : command.length()];
        byte[] header = (command.equals("UNLOCK") ? "UNLOCK " : command).getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(header, 0, frame, 0, header.length);
        if (secret != null) System.arraycopy(secret, 0, frame, 7, 64);
        byte[] response = null;
        long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(8);
        try (var channel = SocketChannel.open(StandardProtocolFamily.UNIX)) {
            channel.configureBlocking(false);
            channel.connect(UnixDomainSocketAddress.of(socket));
            while (!channel.finishConnect()) pause(deadline);
            send(channel, frame, deadline);
            response = receive(channel, 32, deadline);
            String result = new String(response, StandardCharsets.US_ASCII);
            if (!java.util.Set.of("LOCKED", "UNLOCKED", "REFUSED").contains(result))
                throw new IOException("Invalid control response");
            return result;
        } finally {
            Arrays.fill(frame, (byte)0);
            if (response != null) Arrays.fill(response, (byte)0);
        }
    }
    public static void main(String[] args) {
        // Also bounds an abandoned stdin writer. Daemon watchdog does not keep a finished JVM alive.
        Thread watchdog = new Thread(() -> { try { Thread.sleep(15000); Runtime.getRuntime().halt(2); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); } }, "paper-control-deadline");
        watchdog.setDaemon(true); watchdog.start();
        byte[] secret = null;
        int exit = 1;
        try {
            if (args.length != 1) throw new IllegalArgumentException();
            if (args[0].equals("UNLOCK")) secret = System.in.readNBytes(65);
            String state = request(SOCKET, args[0], secret);
            System.out.println("{\"version\":\"PAPER_RUNTIME_CONTROL_V1\",\"state\":\"" + state
                    + "\",\"databaseAuthenticationVerified\":false,\"actionExecutionEnabled\":false}");
            if (!state.equals("REFUSED")) exit = 0;
        } catch (Exception failure) {
            System.out.println("{\"version\":\"PAPER_RUNTIME_CONTROL_V1\",\"state\":\"UNAVAILABLE\",\"actionExecutionEnabled\":false}");
        } finally { if (secret != null) Arrays.fill(secret, (byte)0); }
        System.exit(exit);
    }
}
