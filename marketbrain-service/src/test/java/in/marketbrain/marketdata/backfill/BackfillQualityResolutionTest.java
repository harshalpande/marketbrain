package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class BackfillQualityResolutionTest {

    private final BackfillQualityService service = new BackfillQualityService(null, null, null, null);

    @Test
    void jobWideOfficialSessionResolutionAppliesToEveryMissingInstrument() {
        UUID jobId = UUID.randomUUID();
        LocalDate date = LocalDate.of(2015, 2, 28);
        var detected = List.of(
                finding(QualityFindingType.OFFICIAL_SPECIAL_SESSION, "INFY", date),
                finding(QualityFindingType.OFFICIAL_SPECIAL_SESSION, "TCS", date));
        var resolution = resolution(jobId, null, QualityFindingType.OFFICIAL_SPECIAL_SESSION, date,
                QualityResolutionType.FEATURE_WINDOW_EXCLUDED, true);

        var findings = service.qualityFindings(detected, List.of(resolution), Map.of());

        assertThat(findings).allSatisfy(finding -> {
            assertThat(finding.reviewStatus()).isEqualTo("RESOLVED");
            assertThat(finding.allowsTraining()).isTrue();
        });
    }

    @Test
    void documentedOmissionRemainsOpenForEligibility() {
        UUID jobId = UUID.randomUUID();
        LocalDate date = LocalDate.of(2012, 10, 16);
        var detected = List.of(finding(QualityFindingType.PEER_CONFIRMED_SESSION, "APARINDS", date));
        var resolution = resolution(jobId, "APARINDS", QualityFindingType.PEER_CONFIRMED_SESSION, date,
                QualityResolutionType.PROVIDER_OMISSION_CONFIRMED, false);

        var findings = service.qualityFindings(detected, List.of(resolution), Map.of());

        assertThat(findings).singleElement().satisfies(finding -> {
            assertThat(finding.reviewStatus()).isEqualTo("DOCUMENTED");
            assertThat(finding.allowsTraining()).isFalse();
        });
    }

    @Test
    void corporateActionEvidenceIsShownButDoesNotAutoResolveTheMove() {
        LocalDate date = LocalDate.of(2024, 4, 23);
        var detected = List.of(finding(QualityFindingType.LARGE_MOVE, "ASTERDM", date));

        var findings = service.qualityFindings(
                detected, List.of(), Map.of(new BackfillQualityService.SymbolDate("ASTERDM", date),
                        List.of("DIVIDEND")));

        assertThat(findings).singleElement().satisfies(finding -> {
            assertThat(finding.reviewStatus()).isEqualTo("OPEN");
            assertThat(finding.corporateActionTypes()).containsExactly("DIVIDEND");
        });
    }

    private BackfillQualityService.DetectedFinding finding(
            QualityFindingType type,
            String symbol,
            LocalDate date
    ) {
        return new BackfillQualityService.DetectedFinding(type, symbol, date, null,
                type == QualityFindingType.LARGE_MOVE ? "REVIEW" : "MISSING_PROVIDER_DATA");
    }

    private QualityResolutionRecord resolution(
            UUID jobId,
            String symbol,
            QualityFindingType type,
            LocalDate date,
            QualityResolutionType resolutionType,
            boolean allowsTraining
    ) {
        return new QualityResolutionRecord(
                UUID.randomUUID(), jobId, symbol, type, date, null, resolutionType, allowsTraining,
                "NSE", "https://www.nseindia.com/evidence", "Reviewed", "Harshal",
                resolutionType.requiresExclusion() ? date : null,
                resolutionType.requiresExclusion() ? date : null,
                Instant.parse("2026-09-03T00:00:00Z"));
    }
}
