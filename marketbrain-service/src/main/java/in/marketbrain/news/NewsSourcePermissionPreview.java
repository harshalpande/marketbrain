package in.marketbrain.news;

import java.time.LocalDate;
import java.util.List;

public record NewsSourcePermissionPreview(
        String status,
        String permissionContractVersion,
        LocalDate preparedOn,
        String preparedBy,
        int sourceCount,
        int awaitingResponseCount,
        int termsReviewRequiredCount,
        int approvedCount,
        int rejectedCount,
        int permissionCompleteCount,
        int integrationEligibleCount,
        int integrationEnabledCount,
        boolean registerPersistenceReady,
        boolean contentIngestionAllowed,
        String manifestHash,
        boolean databaseWritesPerformed,
        int providerRequestCount,
        int articlesStored,
        int ollamaCallCount,
        int newsFeaturesCreated,
        int signalsCreated,
        int ordersCreated,
        List<String> failedCheckpoints,
        List<NewsSourcePermissionItemPreview> sources,
        String detail
) {
}
