package in.marketbrain.marketdata.paytm;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.*;

/** Token exchange, account read and bounded quote probe. No orders, redirects or direct fallback. */
public final class PaytmSupervisedClient implements AutoCloseable {
    static final String HOST = "developer.paytmmoney.com";
    static final URI TOKEN = URI.create("https://" + HOST + "/accounts/v2/gettoken");
    private final HttpClient client;
    private final ObjectMapper json = new ObjectMapper();

    public PaytmSupervisedClient() {
        this(createClient());
    }
    PaytmSupervisedClient(HttpClient client) { this.client = client; }
    private static HttpClient createClient() {
        return HttpClient.newBuilder().proxy(new ProxySelector() {
            @Override public List<Proxy> select(URI uri) {
                if (!allowed(uri)) throw new IllegalArgumentException("PAYTM_DESTINATION_DENIED");
                return List.of(new Proxy(Proxy.Type.HTTP, new InetSocketAddress("host.docker.internal", 18889)));
            }
            @Override public void connectFailed(URI uri, SocketAddress address, java.io.IOException error) { }
        }).connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build();
    }
    static boolean allowed(URI uri) {
        return "https".equals(uri.getScheme()) && HOST.equals(uri.getHost()) && uri.getPort() == -1
                && uri.getUserInfo() == null && uri.getFragment() == null
                && (TOKEN.equals(uri) || URI.create("https://" + HOST + "/accounts/v1/user/details").equals(uri)
                    || ("/data/v1/price/live".equals(uri.getRawPath()) && uri.getRawQuery()!=null
                        && uri.getRawQuery().matches("mode=LTP&pref=NSE:[1-9][0-9]{0,7}:EQUITY")));
    }
    JsonNode quote(String readToken, int securityId) {
        if (securityId<1 || securityId>99999999) throw new IllegalArgumentException("PAYTM_SECURITY_ID_INVALID");
        URI uri=URI.create("https://"+HOST+"/data/v1/price/live?mode=LTP&pref=NSE:"+securityId+":EQUITY");
        return send(HttpRequest.newBuilder(uri).header("x-jwt-token",readToken).GET());
    }
    String exchange(String key, String secret, String requestToken) {
        try {
            String body = json.writeValueAsString(Map.of("api_key", key, "api_secret_key", secret, "request_token", requestToken));
            JsonNode reply = send(HttpRequest.newBuilder(TOKEN).header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body)));
            // Discard trading/public tokens. Never substitute a trading token for missing read authority.
            String readToken = reply.path("read_access_token").asText("");
            if (!readToken.matches("[A-Za-z0-9_.=-]{1,16384}")) throw new IllegalStateException("PAYTM_READ_TOKEN_MISSING");
            return readToken;
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) { throw new IllegalStateException("PAYTM_REQUEST_ENCODING_FAILED"); }
    }
    void verifyRead(String readToken) {
        JsonNode value = send(HttpRequest.newBuilder(URI.create("https://" + HOST + "/accounts/v1/user/details"))
                .header("x-jwt-token", readToken).GET());
        if (value == null || !value.isObject() || value.isEmpty() || value.has("error")
                || value.path("status").asText().matches("(?i)false|failure|failed|error")
                || (value.has("success") && !value.path("success").asBoolean()))
            throw new IllegalStateException("PAYTM_ACCOUNT_READ_REJECTED");
    }
    private JsonNode send(HttpRequest.Builder request) {
        try {
            var reply = client.send(request.timeout(Duration.ofSeconds(15)).header("openapi-client-src", "sdk").build(),
                    info -> new BoundedBody());
            if (reply.statusCode() != 200) throw new IllegalStateException("PAYTM_HTTP_" + reply.statusCode());
            if (reply.sslSession().isEmpty() || reply.body().length > 262144) throw new IllegalStateException("PAYTM_RESPONSE_REJECTED");
            return json.readTree(reply.body());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); throw new IllegalStateException("PAYTM_INTERRUPTED");
        } catch (java.io.IOException e) { throw new IllegalStateException("PAYTM_TRANSPORT_OR_JSON_FAILED"); }
    }
    @Override public void close() { client.shutdownNow(); }

    static final class BoundedBody implements HttpResponse.BodySubscriber<byte[]> {
        private final java.util.concurrent.CompletableFuture<byte[]> result = new java.util.concurrent.CompletableFuture<>();
        private final java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
        private java.util.concurrent.Flow.Subscription subscription;
        public java.util.concurrent.CompletionStage<byte[]> getBody() { return result; }
        public void onSubscribe(java.util.concurrent.Flow.Subscription s) { subscription = s; s.request(1); }
        public void onNext(List<java.nio.ByteBuffer> chunks) {
            for (var chunk : chunks) {
                if (chunk.remaining() > 262144 - bytes.size()) {
                    subscription.cancel(); result.completeExceptionally(new java.io.IOException("PAYTM_RESPONSE_TOO_LARGE")); return;
                }
                byte[] part = new byte[chunk.remaining()]; chunk.get(part); bytes.writeBytes(part);
            }
            subscription.request(1);
        }
        public void onError(Throwable failure) { result.completeExceptionally(new java.io.IOException("PAYTM_RESPONSE_FAILED")); }
        public void onComplete() { result.complete(bytes.toByteArray()); }
    }
}
