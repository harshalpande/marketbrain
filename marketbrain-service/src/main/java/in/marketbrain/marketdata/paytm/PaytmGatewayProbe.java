package in.marketbrain.marketdata.paytm;

/** Invoked as a separate bounded JVM in the existing application container, not the Spring process. */
public final class PaytmGatewayProbe {
    public static void main(String[] args) {
        if (args.length != 2 || !args[0].equals("--credential-free-container-head") || !args[1].matches("[0-9]{4,5}")) {
            System.err.println("Invalid probe arguments");
            System.exit(2);
        }
        int port = Integer.parseInt(args[1]);
        if (port != 18889) {
            System.err.println("Unapproved probe port");
            System.exit(2);
        }
        long started = System.nanoTime();
        try (var transport = new PaytmGatewayTransport("host.docker.internal", port)) {
            var result = transport.head();
            System.out.printf("{\"version\":\"PAYTM_CONTAINER_ROUTE_V1\",\"status\":\"%s\","
                            + "\"httpStatus\":%d,\"tlsVerified\":%s,\"failureType\":\"%s\","
                            + "\"elapsedMillis\":%d,\"proxyHost\":\"host.docker.internal\",\"proxyPort\":18889,"
                            + "\"applicationProcessVerified\":false,\"credentialsUsed\":false,\"ordersEnabled\":false}%n",
                    result.status(), result.httpStatus(), result.tlsVerified(), result.failureType(),
                    (System.nanoTime() - started) / 1_000_000);
        }
    }
}
