package in.marketbrain.training;

import java.time.LocalDate;
import java.util.List;

public record HistoricalMembershipSourcePreview(
        String status,
        String membershipContractVersion,
        String universeCode,
        LocalDate asOf,
        String sourceName,
        String sourceUrl,
        String sourceSha256,
        int sourceRecordCount,
        LocalDate earliestEffectiveFrom,
        LocalDate latestClosedEffectiveTo,
        int openEndedPeriodCount,
        int activeMemberCount,
        int matchedActiveMemberCount,
        int unmatchedActiveMemberCount,
        int ambiguousActiveMemberCount,
        int duplicateActiveSymbolCount,
        int duplicateActiveIsinCount,
        int overlappingPeriodCount,
        String historicalMembershipStatus,
        boolean exactAsOfMemberCount,
        boolean allActiveMembersMatched,
        boolean effectiveDateSafe,
        boolean persistenceReady,
        boolean trainingEligible,
        String manifestHash,
        boolean databaseWritesPerformed,
        int ollamaCallCount,
        int signalsCreated,
        int ordersCreated,
        List<String> failedCheckpoints,
        List<HistoricalMembershipMemberPreview> activeMembers,
        String detail
) {
}
