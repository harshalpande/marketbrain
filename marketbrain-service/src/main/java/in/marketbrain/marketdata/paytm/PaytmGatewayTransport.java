package in.marketbrain.marketdata.paytm;

import java.io.IOException;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.List;
import javax.net.ssl.SSLParameters;

/** Credential-free route foundation. Not a Spring bean or a broker/order client. */
public final class PaytmGatewayTransport implements AutoCloseable {
    public static final URI ROOT = URI.create("https://developer.paytmmoney.com/");
    private final HttpClient client;

    public PaytmGatewayTransport(String proxyHost, int proxyPort) {
        if (!List.of("127.0.0.1", "host.docker.internal").contains(proxyHost)
                || proxyPort < 1024 || proxyPort > 65535) {
            throw new IllegalArgumentException("Unsupported gateway endpoint");
        }
        var tls = new SSLParameters();
        tls.setEndpointIdentificationAlgorithm("HTTPS");
        client = HttpClient.newBuilder()
                .proxy(new RequiredProxy(proxyHost, proxyPort))
                .connectTimeout(Duration.ofSeconds(5))
                .followRedirects(HttpClient.Redirect.NEVER)
                .version(HttpClient.Version.HTTP_1_1)
                .sslParameters(tls)
                .build();
    }

    public record Observation(String status, int httpStatus, boolean tlsVerified, String failureType) {}

    public Observation head() {
        try {
            var request = HttpRequest.newBuilder(ROOT).timeout(Duration.ofSeconds(15))
                    .method("HEAD", HttpRequest.BodyPublishers.noBody()).build();
            var response = client.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.sslSession().isEmpty()) {
                return new Observation("TRANSPORT_FAILED", 0, false, "NO_TLS_SESSION");
            }
            return new Observation("TLS_RESPONSE", response.statusCode(), true, "NONE");
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return new Observation("TRANSPORT_FAILED", 0, false, "INTERRUPTED");
        } catch (IOException exception) {
            // Never return exception messages, response bodies, headers, tokens or environment.
            return new Observation("TRANSPORT_FAILED", 0, false, exception.getClass().getSimpleName());
        }
    }

    @Override public void close() { client.shutdownNow(); }

    static final class RequiredProxy extends ProxySelector {
        private final Proxy proxy;
        RequiredProxy(String host, int port) {
            proxy = new Proxy(Proxy.Type.HTTP, new InetSocketAddress(host, port));
        }
        @Override public List<Proxy> select(URI uri) {
            if (!ROOT.equals(uri)) throw new IllegalArgumentException("Destination denied");
            // Never consult the system selector and never return DIRECT, even after connectFailed.
            return List.of(proxy);
        }
        @Override public void connectFailed(URI uri, SocketAddress address, IOException failure) {
            // No retry, proxy rotation, credentials or direct-route fallback.
        }
    }
}
