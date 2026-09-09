package in.marketbrain.training;

import in.marketbrain.marketdata.universe.HistoricalMembershipInstrumentMatch;
import in.marketbrain.marketdata.universe.HistoricalMembershipInstrumentMatcher;
import in.marketbrain.marketdata.universe.Nifty500MembershipCsvParser;
import in.marketbrain.marketdata.universe.Nifty500MembershipRecord;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.StringReader;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class HistoricalMembershipSourcePreviewService {

    static final String CONTRACT_VERSION = "NIFTY500_HISTORICAL_MEMBERSHIP_V1";
    static final String MEMBERSHIP_STATUS = "DATE_EFFECTIVE_SOURCE_PREVIEW";
    private static final int EXPECTED_ACTIVE_MEMBERS = 500;
    private static final int MAXIMUM_SOURCE_BYTES = 10 * 1024 * 1024;

    private final Nifty500MembershipCsvParser parser;
    private final HistoricalMembershipInstrumentMatcher matcher;
    private final HistoricalMembershipPreviewManifestHasher manifestHasher;

    public HistoricalMembershipSourcePreviewService(
            Nifty500MembershipCsvParser parser,
            HistoricalMembershipInstrumentMatcher matcher,
            HistoricalMembershipPreviewManifestHasher manifestHasher
    ) {
        this.parser = parser;
        this.matcher = matcher;
        this.manifestHasher = manifestHasher;
    }

    @Transactional(readOnly = true)
    public HistoricalMembershipSourcePreview preview(
            LocalDate asOf,
            String sourceName,
            String sourceUrl,
            String expectedSourceSha256,
            byte[] payload
    ) {
        validateRequest(asOf, sourceName, sourceUrl, expectedSourceSha256, payload);
        String sourceSha256 = sha256(payload);
        if (!sourceSha256.equals(expectedSourceSha256.toLowerCase(Locale.ROOT))) {
            throw new IllegalArgumentException("The uploaded CSV does not match expectedSourceSha256.");
        }

        List<Nifty500MembershipRecord> records;
        try {
            records = parser.parse(new StringReader(new String(payload, StandardCharsets.UTF_8)));
        } catch (IOException exception) {
            throw new IllegalArgumentException("The historical membership CSV could not be read.", exception);
        }
        List<Nifty500MembershipRecord> active = records.stream()
                .filter(record -> !record.effectiveFrom().isAfter(asOf))
                .filter(record -> record.effectiveTo() == null || !record.effectiveTo().isBefore(asOf))
                .sorted(Comparator.comparing(Nifty500MembershipRecord::symbol)
                        .thenComparing(Nifty500MembershipRecord::isin))
                .toList();

        int duplicateSymbols = duplicateCount(active, Nifty500MembershipRecord::symbol);
        int duplicateIsins = duplicateCount(active, Nifty500MembershipRecord::isin);
        int overlaps = overlappingPeriodCount(records);
        List<HistoricalMembershipInstrumentMatch> matches = matcher.matchAll(active, asOf);
        if (matches.size() != active.size()) {
            throw new IllegalStateException("Historical membership matches do not reconcile with active records.");
        }
        List<HistoricalMembershipMemberPreview> members = new ArrayList<>(active.size());
        for (int index = 0; index < active.size(); index++) {
            Nifty500MembershipRecord record = active.get(index);
            HistoricalMembershipInstrumentMatch match = matches.get(index);
            members.add(new HistoricalMembershipMemberPreview(
                    record.symbol(), record.isin(), record.companyName(),
                    record.effectiveFrom(), record.effectiveTo(), match.matchStatus(),
                    match.instrumentId(), match.currentSymbol(), match.matchBasis()));
        }
        members = members.stream()
                .sorted(Comparator.comparing(HistoricalMembershipMemberPreview::sourceSymbol))
                .toList();

        int matched = count(members, "MATCHED");
        int ambiguous = count(members, "AMBIGUOUS");
        int unmatched = count(members, "UNMATCHED");
        boolean exactCount = active.size() == EXPECTED_ACTIVE_MEMBERS;
        boolean allMatched = matched == active.size() && ambiguous == 0 && unmatched == 0;
        boolean effectiveDateSafe = duplicateSymbols == 0 && duplicateIsins == 0 && overlaps == 0;
        boolean persistenceReady = exactCount && allMatched && effectiveDateSafe;
        List<String> failedCheckpoints = failedCheckpoints(
                exactCount, allMatched, duplicateSymbols, duplicateIsins, overlaps);
        String manifestHash = manifestHasher.hash(
                asOf, sourceName.trim(), sourceUrl.trim(), sourceSha256, records, members);

        return new HistoricalMembershipSourcePreview(
                persistenceReady ? "REVIEW_REQUIRED" : "SOURCE_REVIEW_REQUIRED",
                CONTRACT_VERSION,
                "NIFTY_500",
                asOf,
                sourceName.trim(),
                sourceUrl.trim(),
                sourceSha256,
                records.size(),
                records.stream().map(Nifty500MembershipRecord::effectiveFrom)
                        .min(LocalDate::compareTo).orElseThrow(),
                records.stream().map(Nifty500MembershipRecord::effectiveTo)
                        .filter(value -> value != null).max(LocalDate::compareTo).orElse(null),
                (int) records.stream().filter(record -> record.effectiveTo() == null).count(),
                active.size(),
                matched,
                unmatched,
                ambiguous,
                duplicateSymbols,
                duplicateIsins,
                overlaps,
                MEMBERSHIP_STATUS,
                exactCount,
                allMatched,
                effectiveDateSafe,
                persistenceReady,
                false,
                manifestHash,
                false,
                0,
                0,
                0,
                failedCheckpoints,
                members,
                persistenceReady
                        ? "The date-effective source is structurally and referentially ready for explicit review."
                        : "The date-effective source cannot be persisted until every failed checkpoint is resolved."
        );
    }

    private void validateRequest(
            LocalDate asOf,
            String sourceName,
            String sourceUrl,
            String expectedSourceSha256,
            byte[] payload
    ) {
        if (asOf == null) {
            throw new IllegalArgumentException("asOf is required.");
        }
        requireText(sourceName, "sourceName");
        requireText(sourceUrl, "sourceUrl");
        if (expectedSourceSha256 == null || !expectedSourceSha256.matches("^[0-9a-fA-F]{64}$")) {
            throw new IllegalArgumentException("expectedSourceSha256 must contain 64 hexadecimal characters.");
        }
        if (payload == null || payload.length == 0) {
            throw new IllegalArgumentException("The historical membership CSV is empty.");
        }
        if (payload.length > MAXIMUM_SOURCE_BYTES) {
            throw new IllegalArgumentException("The historical membership CSV exceeds 10 MB.");
        }
        try {
            URI uri = new URI(sourceUrl.trim());
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
                throw new IllegalArgumentException("sourceUrl must be an absolute HTTPS evidence URL.");
            }
        } catch (URISyntaxException exception) {
            throw new IllegalArgumentException("sourceUrl must be an absolute HTTPS evidence URL.");
        }
    }

    private void requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " is required.");
        }
    }

    private int duplicateCount(
            List<Nifty500MembershipRecord> records,
            Function<Nifty500MembershipRecord, String> classifier
    ) {
        return (int) records.stream()
                .collect(Collectors.groupingBy(classifier, Collectors.counting()))
                .values().stream()
                .filter(count -> count > 1)
                .count();
    }

    private int overlappingPeriodCount(List<Nifty500MembershipRecord> records) {
        Map<String, List<Nifty500MembershipRecord>> byIsin = new HashMap<>();
        records.forEach(record -> byIsin.computeIfAbsent(record.isin(), ignored -> new ArrayList<>()).add(record));
        int overlaps = 0;
        for (List<Nifty500MembershipRecord> periods : byIsin.values()) {
            periods.sort(Comparator.comparing(Nifty500MembershipRecord::effectiveFrom));
            Nifty500MembershipRecord previous = null;
            for (Nifty500MembershipRecord period : periods) {
                if (previous != null && (previous.effectiveTo() == null
                        || !period.effectiveFrom().isAfter(previous.effectiveTo()))) {
                    overlaps++;
                }
                if (previous == null || endAfter(period.effectiveTo(), previous.effectiveTo())) {
                    previous = period;
                }
            }
        }
        return overlaps;
    }

    private boolean endAfter(LocalDate candidate, LocalDate current) {
        return candidate == null || (current != null && candidate.isAfter(current));
    }

    private int count(List<HistoricalMembershipMemberPreview> members, String status) {
        return (int) members.stream().filter(member -> status.equals(member.matchStatus())).count();
    }

    private List<String> failedCheckpoints(
            boolean exactCount,
            boolean allMatched,
            int duplicateSymbols,
            int duplicateIsins,
            int overlaps
    ) {
        List<String> failures = new ArrayList<>();
        if (!exactCount) {
            failures.add("ACTIVE_MEMBER_COUNT");
        }
        if (!allMatched) {
            failures.add("ACTIVE_MEMBER_MATCHING");
        }
        if (duplicateSymbols > 0) {
            failures.add("DUPLICATE_ACTIVE_SYMBOLS");
        }
        if (duplicateIsins > 0) {
            failures.add("DUPLICATE_ACTIVE_ISINS");
        }
        if (overlaps > 0) {
            failures.add("OVERLAPPING_ISIN_PERIODS");
        }
        return List.copyOf(failures);
    }

    private String sha256(byte[] payload) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }
}
