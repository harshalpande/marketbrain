package in.marketbrain.training;

import in.marketbrain.marketdata.universe.Nifty500MembershipRecord;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;

@Component
public class HistoricalMembershipPreviewManifestHasher {

    public String hash(
            LocalDate asOf,
            String sourceName,
            String sourceUrl,
            String sourceSha256,
            List<Nifty500MembershipRecord> records,
            List<HistoricalMembershipMemberPreview> activeMembers
    ) {
        StringBuilder canonical = new StringBuilder();
        append(canonical, "NIFTY500_HISTORICAL_MEMBERSHIP_V1");
        append(canonical, asOf);
        append(canonical, sourceName);
        append(canonical, sourceUrl);
        append(canonical, sourceSha256);
        records.stream()
                .sorted(Comparator.comparing(Nifty500MembershipRecord::isin)
                        .thenComparing(Nifty500MembershipRecord::effectiveFrom)
                        .thenComparing(Nifty500MembershipRecord::symbol))
                .forEach(record -> {
                    append(canonical, record.symbol());
                    append(canonical, record.isin());
                    append(canonical, record.companyName());
                    append(canonical, record.effectiveFrom());
                    append(canonical, record.effectiveTo());
                });
        activeMembers.stream()
                .sorted(Comparator.comparing(HistoricalMembershipMemberPreview::sourceIsin)
                        .thenComparing(HistoricalMembershipMemberPreview::sourceSymbol))
                .forEach(member -> {
                    append(canonical, member.sourceIsin());
                    append(canonical, member.sourceSymbol());
                    append(canonical, member.matchStatus());
                    append(canonical, member.instrumentId());
                    append(canonical, member.currentSymbol());
                    append(canonical, member.matchBasis());
                });
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }

    private void append(StringBuilder target, Object value) {
        String text = value == null ? "<null>" : value.toString();
        target.append(text.length()).append(':').append(text).append('|');
    }
}
