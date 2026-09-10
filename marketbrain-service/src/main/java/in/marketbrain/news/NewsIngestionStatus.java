package in.marketbrain.news;

import java.util.List;

public record NewsIngestionStatus(
        String status,
        boolean newsModuleEnabled,
        boolean liveFetchEnabled,
        int maximumArticlesPerDay,
        int sourceCount,
        int implementedConnectorCount,
        int persistedSourceCount,
        int enabledSourceCount,
        int liveFetchEligibleCount,
        int providerRequestCount,
        int articlesStored,
        int ollamaCallCount,
        int newsFeaturesCreated,
        int signalsCreated,
        int ordersCreated,
        List<NewsIngestionSourceStatus> sources,
        String detail
) {
}
