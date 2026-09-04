package in.marketbrain.marketdata.backfill;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class LargeMoveEvidenceServiceTest {

    private final LargeMoveEvidenceService service = new LargeMoveEvidenceService(null, null, null);

    @Test
    void matchesHistoricalSymbolByIsinAndDoesNotWriteAResolution() {
        LocalDate date = LocalDate.of(2019, 10, 11);
        var finding = finding("ABREL", date, "882.20", "393.85", "55.36");
        var official = new NseBhavcopyRecord(
                "CENTURYTEX", "INE055A01016", "EQ", date,
                new BigDecimal("882.20"), new BigDecimal("400.00"), new BigDecimal("410.00"),
                new BigDecimal("390.00"), new BigDecimal("393.85"), new BigDecimal("100000"));
        var archive = archive(date, official);

        var result = service.evaluate(finding, "INE055A01016", archive, List.of());

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_PRICES_MATCH");
        assertThat(result.officialSymbol()).isEqualTo("CENTURYTEX");
        assertThat(result.matchBasis()).isEqualTo("ISIN");
        assertThat(result.reviewPath()).isEqualTo("REVIEW_VERIFIED_EXCHANGE_MOVE");
    }

    @Test
    void sendsOfficialPriceDifferencesToProviderAdjustmentReview() {
        LocalDate date = LocalDate.of(2025, 1, 29);
        var finding = finding("ACUTAAS", date, "940.90", "1129.10", "20.00");
        var official = new NseBhavcopyRecord(
                "ACUTAAS", "INE00FF01025", "EQ", date,
                new BigDecimal("1000.00"), null, null, null, new BigDecimal("1100.00"), null);

        var result = service.evaluate(finding, "INE00FF01025", archive(date, official), List.of());

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_CLOSE_MISMATCH");
        assertThat(result.reviewPath()).isEqualTo("REVIEW_PROVIDER_ADJUSTMENT");
        assertThat(result.closeDifferencePercent()).isPositive();
    }

    @Test
    void recognizesAConsistentlyRescaledSeriesByItsReturn() {
        LocalDate date = LocalDate.of(2013, 5, 17);
        var finding = finding("ABB", date, "426.35", "515.60", "20.93");
        var official = new NseBhavcopyRecord(
                "ABB", "INE117A01022", "EQ", date,
                new BigDecimal("545.25"), null, null, null, new BigDecimal("659.40"), null);

        var result = service.evaluate(finding, "INE117A01022", archive(date, official), List.of());

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES");
        assertThat(result.reviewPath()).isEqualTo("REVIEW_VERIFIED_ADJUSTED_EXCHANGE_MOVE");
        assertThat(result.returnDifferencePercentagePoints()).isLessThan(new BigDecimal("0.01"));
        assertThat(result.scaleRatioDifferencePercent()).isLessThan(new BigDecimal("0.01"));
    }

    @Test
    void doesNotTreatAnInconsistentScaleAsAnAdjustedReturnMatch() {
        LocalDate date = LocalDate.of(2012, 9, 10);
        var finding = finding("ACE", date, "18.00", "23.55", "30.83");
        var official = new NseBhavcopyRecord(
                "ACE", "INE731H01025", "EQ", date,
                new BigDecimal("19.65"), null, null, null, new BigDecimal("23.55"), null);

        var result = service.evaluate(finding, "INE731H01025", archive(date, official), List.of());

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_PREVIOUS_CLOSE_MISMATCH");
        assertThat(result.returnDifferencePercentagePoints()).isGreaterThan(new BigDecimal("10"));
        assertThat(result.reviewPath()).isEqualTo("REVIEW_PROVIDER_ADJUSTMENT");
    }

    @Test
    void matchesAnEffectiveDatedHistoricalIsin() {
        LocalDate date = LocalDate.of(2025, 1, 29);
        var finding = finding("ACUTAAS", date, "940.90", "1129.10", "20.00");
        var official = new NseBhavcopyRecord(
                "AMIORG", "INE00FF01017", "EQ", date,
                new BigDecimal("1881.85"), null, null, null, new BigDecimal("2258.20"), null);
        var aliases = List.of(new LargeMoveEvidenceService.HistoricalIdentity(
                "AMIORG", "INE00FF01017", LocalDate.of(2025, 1, 29), LocalDate.of(2025, 4, 24)));

        var result = service.evaluate(
                finding, "INE00FF01025", aliases, archive(date, official), List.of());

        assertThat(result.officialSymbol()).isEqualTo("AMIORG");
        assertThat(result.matchBasis()).isEqualTo("HISTORICAL_ISIN");
        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_RETURN_MATCH_ADJUSTED_PRICES");
    }

    @Test
    void ignoresAHistoricalIdentityOutsideItsEvidenceBackedPeriod() {
        LocalDate date = LocalDate.of(2024, 1, 29);
        var finding = finding("ACUTAAS", date, "940.90", "1129.10", "20.00");
        var official = new NseBhavcopyRecord(
                "AMIORG", "INE00FF01017", "EQ", date,
                new BigDecimal("1881.85"), null, null, null, new BigDecimal("2258.20"), null);
        var aliases = List.of(new LargeMoveEvidenceService.HistoricalIdentity(
                "AMIORG", "INE00FF01017", LocalDate.of(2025, 1, 29), LocalDate.of(2025, 4, 24)));

        var result = service.evaluate(
                finding, "INE00FF01025", aliases, archive(date, official), List.of());

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_INSTRUMENT_NOT_FOUND");
        assertThat(result.reviewPath()).isEqualTo("KEEP_OPEN");
    }

    @Test
    void corporateActionOnTheFindingDateTakesTheCorporateActionReviewPath() {
        LocalDate date = LocalDate.of(2024, 4, 23);
        var finding = finding("ASTERDM", date, "513.35", "399.50", "22.18");
        var official = new NseBhavcopyRecord(
                "ASTERDM", "INE914M01019", "EQ", date,
                new BigDecimal("513.35"), null, null, null, new BigDecimal("399.50"), null);

        var result = service.evaluate(finding, "INE914M01019", archive(date, official), List.of("DIVIDEND"));

        assertThat(result.evidenceStatus()).isEqualTo("OFFICIAL_PRICES_MATCH");
        assertThat(result.reviewPath()).isEqualTo("REVIEW_CORPORATE_ACTION_TRANSITION");
    }

    @Test
    void unavailableOfficialArchiveKeepsFindingOpen() {
        LocalDate date = LocalDate.of(2020, 3, 23);
        var result = service.evaluate(
                finding("ASHOKLEY", date, "19.50", "15.55", "20.26"),
                "INE208A01029",
                NseBhavcopyArchive.failure(
                        "CONNECTION_FAILED", date, "LEGACY", NseBhavcopyClient.sourceUrl(date), "retry safely"),
                List.of());

        assertThat(result.evidenceStatus()).isEqualTo("CONNECTION_FAILED");
        assertThat(result.reviewPath()).isEqualTo("KEEP_OPEN");
        assertThat(result.officialClose()).isNull();
    }

    private BackfillQualityReport.LargeMoveFinding finding(
            String symbol,
            LocalDate date,
            String previousClose,
            String close,
            String movePercent
    ) {
        return new BackfillQualityReport.LargeMoveFinding(
                symbol, date, new BigDecimal(previousClose), new BigDecimal(close), new BigDecimal(movePercent));
    }

    private NseBhavcopyArchive archive(LocalDate date, NseBhavcopyRecord... records) {
        return new NseBhavcopyArchive(
                "SUCCESS", date, NseBhavcopyClient.formatFor(date), NseBhavcopyClient.sourceUrl(date),
                List.of(records), "read only");
    }
}
