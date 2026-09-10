package in.marketbrain.news;

import java.util.List;
import java.util.UUID;

public record NewsIngestionRunResult(
        String status,
        UUID runId,
        boolean newsModuleEnabled,
        boolean liveFetchEnabled,
        int sourceCount,
        int attemptedSourceCount,
        int providerRequestCount,
        int candidateArticleCount,
        int storedArticleCount,
        int ollamaCallCount,
        int newsFeaturesCreated,
        int signalsCreated,
        int ordersCreated,
        List<NewsSourceRunResult> sources,
        String detail
) {
}
