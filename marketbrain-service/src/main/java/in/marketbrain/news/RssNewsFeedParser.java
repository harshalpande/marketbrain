package in.marketbrain.news;

import org.springframework.stereotype.Component;
import org.w3c.dom.Element;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilderFactory;
import java.io.StringReader;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

@Component
public class RssNewsFeedParser {

    public List<NewsArticleCandidate> parse(String sourceKey, String payload) {
        try {
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            factory.setExpandEntityReferences(false);
            var builder = factory.newDocumentBuilder();
            var document = builder.parse(new InputSource(new StringReader(payload)));
            var items = document.getElementsByTagName("item");
            List<NewsArticleCandidate> articles = new ArrayList<>();
            for (int index = 0; index < items.getLength(); index++) {
                Element item = (Element) items.item(index);
                String link = text(item, "link");
                String title = text(item, "title");
                if (link.isBlank() || title.isBlank()) {
                    continue;
                }
                String guid = text(item, "guid");
                articles.add(new NewsArticleCandidate(
                        sourceKey,
                        guid.isBlank() ? link : guid,
                        link,
                        NewsUrlSupport.domain(link),
                        title,
                        firstNonBlank(text(item, "description"), text(item, "summary")),
                        instant(firstNonBlank(text(item, "pubDate"), text(item, "published"))),
                        List.of()));
            }
            return List.copyOf(articles);
        } catch (Exception exception) {
            throw new IllegalArgumentException("RSS payload could not be parsed.", exception);
        }
    }

    private String text(Element parent, String tagName) {
        var nodes = parent.getElementsByTagName(tagName);
        if (nodes.getLength() == 0) {
            return "";
        }
        String text = nodes.item(0).getTextContent();
        return text == null ? "" : text.trim();
    }

    private Instant instant(String value) {
        if (value.isBlank()) {
            return null;
        }
        try {
            return ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant();
        } catch (DateTimeParseException exception) {
            try {
                return Instant.parse(value);
            } catch (DateTimeParseException ignored) {
                return null;
            }
        }
    }

    private String firstNonBlank(String first, String second) {
        return first.isBlank() ? second : first;
    }
}
