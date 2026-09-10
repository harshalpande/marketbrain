package in.marketbrain.news;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Locale;

final class NewsUrlSupport {

    private NewsUrlSupport() {
    }

    static String domain(String url) {
        try {
            String host = new URI(url).getHost();
            if (host == null || host.isBlank()) {
                return "unknown";
            }
            return host.toLowerCase(Locale.ROOT);
        } catch (URISyntaxException exception) {
            return "unknown";
        }
    }
}
