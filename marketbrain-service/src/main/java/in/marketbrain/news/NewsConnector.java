package in.marketbrain.news;

public interface NewsConnector {
    NewsSourceIntegrationType integrationType();

    default boolean liveFetchCapable() {
        return true;
    }

    NewsFetchResult fetch(NewsFetchRequest request);
}
