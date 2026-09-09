package in.marketbrain.training;

import in.marketbrain.marketdata.universe.HistoricalMembershipInstrumentMatch;
import in.marketbrain.marketdata.universe.HistoricalMembershipInstrumentMatcher;
import in.marketbrain.marketdata.universe.Nifty500MembershipCsvParser;
import in.marketbrain.marketdata.universe.Nifty500MembershipRecord;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class HistoricalMembershipSourcePreviewServiceTest {

    @Test
    void validatesExactlyFiveHundredDateEffectiveMatchedMembersWithoutWriting() throws Exception {
        LocalDate asOf = LocalDate.of(2026, 6, 5);
        byte[] payload = source(500).getBytes(StandardCharsets.UTF_8);
        HistoricalMembershipInstrumentMatcher matcher = mock(HistoricalMembershipInstrumentMatcher.class);
        when(matcher.matchAll(anyList(), eq(asOf))).thenAnswer(invocation -> {
            List<Nifty500MembershipRecord> records = invocation.getArgument(0);
            List<HistoricalMembershipInstrumentMatch> matches = new ArrayList<>();
            for (int index = 0; index < records.size(); index++) {
                matches.add(HistoricalMembershipInstrumentMatch.matched(
                        index + 1L, records.get(index).symbol(), "CURRENT_ISIN"));
            }
            return List.copyOf(matches);
        });
        var service = new HistoricalMembershipSourcePreviewService(
                new Nifty500MembershipCsvParser(), matcher,
                new HistoricalMembershipPreviewManifestHasher());

        HistoricalMembershipSourcePreview result = service.preview(
                asOf, "Authorized NSE Indices history", "https://example.test/history.csv",
                sha256(payload), payload);

        assertThat(result.status()).isEqualTo("REVIEW_REQUIRED");
        assertThat(result.activeMemberCount()).isEqualTo(500);
        assertThat(result.matchedActiveMemberCount()).isEqualTo(500);
        assertThat(result.unmatchedActiveMemberCount()).isZero();
        assertThat(result.failedCheckpoints()).isEmpty();
        assertThat(result.persistenceReady()).isTrue();
        assertThat(result.trainingEligible()).isFalse();
        assertThat(result.databaseWritesPerformed()).isFalse();
        assertThat(result.manifestHash()).matches("[0-9a-f]{64}");
    }

    private String source(int count) {
        StringBuilder csv = new StringBuilder(
                "symbol,isin,companyName,effectiveFrom,effectiveTo\n");
        for (int index = 0; index < count; index++) {
            csv.append("SYMBOL").append(index)
                    .append(",INE").append(String.format("%09d", index))
                    .append(",Company ").append(index)
                    .append(",2026-04-01,\n");
        }
        return csv.toString();
    }

    private String sha256(byte[] payload) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload));
    }
}
