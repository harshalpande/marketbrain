package in.marketbrain.marketdata.paytm;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Real loopback proxy fixtures only; no connection to Paytm, VPS or any external destination. */
public final class PaytmRouteVerification {
    private static int checks;
    private static void check(boolean condition) { if (!condition) throw new AssertionError("Route contract failed"); checks++; }
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !args[0].equals("--local-only")) throw new IllegalArgumentException("Local-only verifier");
        run();
        System.out.printf("{\"version\":\"PAYTM_ROUTE_LOCAL_V1\",\"checks\":%d,\"passed\":true,\"externalCalls\":0}%n", checks);
    }
    static synchronized int run() throws Exception {
        checks = 0;
        var selector = new PaytmGatewayTransport.RequiredProxy("127.0.0.1", 18889);
        check(selector.select(PaytmGatewayTransport.ROOT).size() == 1);
        check(selector.select(PaytmGatewayTransport.ROOT).getFirst().type() == Proxy.Type.HTTP);
        selector.connectFailed(PaytmGatewayTransport.ROOT, new InetSocketAddress("127.0.0.1", 18889), new IOException());
        check(selector.select(PaytmGatewayTransport.ROOT).getFirst().type() == Proxy.Type.HTTP);
        for (String denied : List.of("http://developer.paytmmoney.com/", "https://example.com/",
                "https://developer.paytmmoney.com:80/", "https://developer.paytmmoney.com.invalid/",
                "https://developer.paytmmoney.com/accounts/v2/gettoken", "https://developer.paytmmoney.com/?token=fixture")) {
            boolean rejected = false;
            try { selector.select(URI.create(denied)); } catch (IllegalArgumentException expected) { rejected = true; }
            check(rejected);
        }
        boolean rejected = false;
        try (var ignored = new PaytmGatewayTransport("unapproved.invalid", 18889)) { }
        catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected);
        // A process-wide direct selector must never be consulted by our explicit required proxy.
        var old = ProxySelector.getDefault();
        var defaultCalls = new AtomicInteger();
        ProxySelector.setDefault(new ProxySelector() {
            public List<Proxy> select(URI uri) { defaultCalls.incrementAndGet(); throw new AssertionError("Direct fallback attempted"); }
            public void connectFailed(URI uri, SocketAddress address, IOException failure) { throw new AssertionError(); }
        });
        try {
            for (int proxyStatus : new int[]{403, 200}) {
            try (var server = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))) {
                server.setSoTimeout(5000);
                try (var executor = Executors.newSingleThreadExecutor()) {
                    Future<String> connect = executor.submit(() -> {
                        try (var socket = server.accept()) {
                            socket.setSoTimeout(5000);
                            var input = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII));
                            String first = input.readLine();
                            for (int i = 0; i < 32; i++) { String line = input.readLine(); if (line == null || line.isEmpty()) break; }
                            // 200 deliberately has no TLS server behind it: CONNECT alone must not pass.
                            socket.getOutputStream().write(("HTTP/1.1 " + proxyStatus + " Fixture\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                            socket.getOutputStream().flush();
                            return first;
                        }
                    });
                    try (var transport = new PaytmGatewayTransport("127.0.0.1", server.getLocalPort())) {
                        var response = transport.head();
                        check(response.status().equals("TRANSPORT_FAILED"));
                        check(response.httpStatus() == 0 && !response.tlsVerified());
                    }
                    check(connect.get(6, TimeUnit.SECONDS).equals("CONNECT developer.paytmmoney.com:443 HTTP/1.1"));
                }
            }
            }
            int port;
            try (var reservation = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))) { port = reservation.getLocalPort(); }
            try (var transport = new PaytmGatewayTransport("127.0.0.1", port)) {
                var result = transport.head();
                check(result.status().equals("TRANSPORT_FAILED") && !result.tlsVerified() && result.httpStatus() == 0);
            }
            check(defaultCalls.get() == 0);
        } finally { ProxySelector.setDefault(old); }
        return checks;
    }
}
