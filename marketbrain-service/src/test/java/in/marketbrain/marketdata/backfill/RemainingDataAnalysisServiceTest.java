package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class RemainingDataAnalysisServiceTest {

    private final LargeMoveEvidenceService evidenceService = new LargeMoveEvidenceService(null, null, null);
    private final RemainingDataAnalysisService service =
            new RemainingDataAnalysisService(null, null, evidenceService, null);

    @Test
    void recommendsSecondaryBackfillOnlyWhenTheOfficialCandleIsValid() {
        LocalDate date = LocalDate.of(2019, 10, 4);
        var finding = finding(QualityFindingType.PEER_CONFIRMED_SESSION, "360ONE", date, null);
        var official = new NseBhavcopyRecord(
                "IIFLWAM", "INE466L01038", "EQ", date, new BigDecimal("1200.00"),
                new BigDecimal("1201.00"), new BigDecimal("1210.00"), new BigDecimal("1190.00"),
                new BigDecimal("1205.00"), new BigDecimal("1000"));

        var result = service.analyzeMissingSession(
                finding, "INE466L01038", List.of(), archive(date, official));

        assertThat(result.analysisStatus()).isEqualTo("OFFICIAL_CANDLE_AVAILABLE");
        assertThat(result.recommendedResolutionType())
                .isEqualTo(QualityResolutionType.SECONDARY_SOURCE_BACKFILLED);
        assertThat(result.officialSymbol()).isEqualTo("IIFLWAM");
        assertThat(result.matchBasis()).isEqualTo("ISIN");
        assertThat(result.officialClose()).isEqualByComparingTo("1205.00");
        assertThat(result.exclusionFrom()).isNull();
    }

    @Test
    void ignoresAnUnsupportedSeriesWhenAnEquityRecordIsAvailable() {
        LocalDate date = LocalDate.of(2019, 10, 4);
        var finding = finding(QualityFindingType.PEER_CONFIRMED_SESSION, "360ONE", date, null);
        var unsupported = new NseBhavcopyRecord(
                "IIFLWAM", "INE466L01038", "BL", date, BigDecimal.ONE,
                BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE);
        var equity = new NseBhavcopyRecord(
                "IIFLWAM", "INE466L01038", "EQ", date, new BigDecimal("1200.00"),
                new BigDecimal("1201.00"), new BigDecimal("1210.00"), new BigDecimal("1190.00"),
                new BigDecimal("1205.00"), new BigDecimal("1000"));

        var result = service.analyzeMissingSession(
                finding, "INE466L01038", List.of(), archive(date, unsupported, equity));

        assertThat(result.officialSeries()).isEqualTo("EQ");
        assertThat(result.officialClose()).isEqualByComparingTo("1205.00");
    }

    @Test
    void excludesOneSessionWhenTheOfficialArchiveHasNoSupportedInstrument() {
        LocalDate date = LocalDate.of(2012, 10, 16);
        var finding = finding(QualityFindingType.PEER_CONFIRMED_SESSION, "APARINDS", date, null);

        var result = service.analyzeMissingSession(
                finding, "INE372A01015", List.of(), archive(date));

        assertThat(result.analysisStatus()).isEqualTo("OFFICIAL_INSTRUMENT_NOT_FOUND");
        assertThat(result.recommendedResolutionType())
                .isEqualTo(QualityResolutionType.FEATURE_WINDOW_EXCLUDED);
        assertThat(result.exclusionFrom()).isEqualTo(date);
        assertThat(result.exclusionTo()).isEqualTo(date);
    }

    @Test
    void keepsAnInvalidOfficialCandleOpen() {
        LocalDate date = LocalDate.of(2020, 1, 1);
        var finding = finding(QualityFindingType.OFFICIAL_SPECIAL_SESSION, "INFY", date, null);
        var invalid = new NseBhavcopyRecord(
                "INFY", "INE009A01021", "EQ", date, null,
                new BigDecimal("100"), new BigDecimal("90"), new BigDecimal("80"),
                new BigDecimal("85"), BigDecimal.ONE);

        var result = service.analyzeMissingSession(
                finding, "INE009A01021", List.of(), archive(date, invalid));

        assertThat(result.analysisStatus()).isEqualTo("OFFICIAL_CANDLE_INVALID");
        assertThat(result.recommendedResolutionType()).isNull();
    }

    @Test
    void convertsALeadingCoverageGapIntoAnExplicitBoundedExclusion() {
        LocalDate requestedFrom = LocalDate.of(2011, 9, 2);
        LocalDate firstCandle = LocalDate.of(2019, 9, 19);
        var finding = finding(
                QualityFindingType.LEADING_COVERAGE_GAP, "360ONE", requestedFrom, firstCandle);

        var result = service.analyzeCoverageGap(finding);

        assertThat(result.analysisStatus()).isEqualTo("COVERAGE_WINDOW_REQUIRES_EXCLUSION");
        assertThat(result.recommendedResolutionType())
                .isEqualTo(QualityResolutionType.FEATURE_WINDOW_EXCLUDED);
        assertThat(result.exclusionFrom()).isEqualTo(requestedFrom);
        assertThat(result.exclusionTo()).isEqualTo(firstCandle.minusDays(1));
    }

    @Test
    void sendsAConfirmedOfficialMismatchToAOneDayProviderAdjustmentExclusion() {
        LocalDate date = LocalDate.of(2012, 9, 10);
        var qualityFinding = finding(QualityFindingType.LARGE_MOVE, "ACE", date, null);
        var largeMove = new BackfillQualityReport.LargeMoveFinding(
                "ACE", date, new BigDecimal("18.00"), new BigDecimal("23.55"), new BigDecimal("30.83"));
        var official = new NseBhavcopyRecord(
                "ACE", "INE731H01025", "EQ", date, new BigDecimal("19.65"),
                new BigDecimal("20.00"), new BigDecimal("24.00"), new BigDecimal("19.00"),
                new BigDecimal("23.55"), BigDecimal.TEN);

        var result = service.analyzeLargeMove(
                qualityFinding, "INE731H01025", List.of(), archive(date, official), largeMove);

        assertThat(result.analysisStatus()).isEqualTo("OFFICIAL_PREVIOUS_CLOSE_MISMATCH");
        assertThat(result.recommendedResolutionType()).isEqualTo(QualityResolutionType.PROVIDER_ADJUSTMENT);
        assertThat(result.exclusionFrom()).isEqualTo(date);
        assertThat(result.exclusionTo()).isEqualTo(date);
    }

    private BackfillQualityReport.QualityFinding finding(
            QualityFindingType type,
            String symbol,
            LocalDate findingDate,
            LocalDate relatedDate
    ) {
        return new BackfillQualityReport.QualityFinding(
                type, symbol, findingDate, relatedDate, "REVIEW", "OPEN", null, false,
                null, null, null, null, List.of());
    }

    private NseBhavcopyArchive archive(LocalDate date, NseBhavcopyRecord... records) {
        return new NseBhavcopyArchive(
                "SUCCESS", date, NseBhavcopyClient.formatFor(date), NseBhavcopyClient.sourceUrl(date),
                List.of(records), "read only");
    }
}
