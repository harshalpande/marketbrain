package in.marketbrain.marketdata.backfill;

import org.springframework.stereotype.Component;

import java.time.LocalDate;

@Component
public class QualityResolutionPolicy {

    public void validate(
            QualityFindingType findingType,
            QualityResolutionType resolutionType,
            LocalDate findingDate,
            LocalDate exclusionFrom,
            LocalDate exclusionTo,
            LocalDate jobFrom,
            LocalDate jobTo
    ) {
        boolean missingSession = findingType == QualityFindingType.OFFICIAL_SPECIAL_SESSION
                || findingType == QualityFindingType.PEER_CONFIRMED_SESSION;
        if ((resolutionType == QualityResolutionType.SECONDARY_SOURCE_BACKFILLED
                || resolutionType == QualityResolutionType.PROVIDER_OMISSION_CONFIRMED) && !missingSession) {
            throw new IllegalArgumentException(resolutionType + " is only valid for a missing-session finding");
        }
        if ((resolutionType == QualityResolutionType.VERIFIED_EXCHANGE_MOVE
                || resolutionType == QualityResolutionType.CORPORATE_ACTION_TRANSITION
                || resolutionType == QualityResolutionType.PROVIDER_ADJUSTMENT)
                && findingType != QualityFindingType.LARGE_MOVE) {
            throw new IllegalArgumentException(resolutionType + " is only valid for a large-move finding");
        }
        if (resolutionType.requiresExclusion() && (exclusionFrom == null || exclusionTo == null)) {
            throw new IllegalArgumentException(resolutionType + " requires an explicit feature-exclusion window");
        }
        if (!resolutionType.requiresExclusion() && (exclusionFrom != null || exclusionTo != null)) {
            throw new IllegalArgumentException(resolutionType + " must not define a feature-exclusion window");
        }
        if (exclusionFrom != null && (exclusionTo.isBefore(exclusionFrom)
                || exclusionFrom.isBefore(jobFrom) || exclusionTo.isAfter(jobTo))) {
            throw new IllegalArgumentException("Feature-exclusion dates must be ordered and inside the job window");
        }
        if (exclusionFrom != null
                && (findingDate.isBefore(exclusionFrom) || findingDate.isAfter(exclusionTo))) {
            throw new IllegalArgumentException("Feature-exclusion window must contain the finding date");
        }
    }
}
