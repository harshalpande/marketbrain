package in.marketbrain.marketdata.daily;

import in.marketbrain.configuration.DailyEnrichmentProperties;
import in.marketbrain.marketdata.upstox.UpstoxCandle;
import in.marketbrain.marketdata.upstox.UpstoxFetchResult;
import in.marketbrain.marketdata.upstox.UpstoxIntradayRequest;
import in.marketbrain.marketdata.upstox.UpstoxReadOnlyClient;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Service
public class DailyEnrichmentProviderReadinessService {

    private static final ZoneId INDIA = ZoneId.of("Asia/Kolkata");

    private final JdbcTemplate jdbcTemplate;
    private final UpstoxReadOnlyClient upstoxClient;
    private final DailyEnrichmentProperties properties;

    public DailyEnrichmentProviderReadinessService(
            JdbcTemplate jdbcTemplate,
            UpstoxReadOnlyClient upstoxClient,
            DailyEnrichmentProperties properties
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.upstoxClient = upstoxClient;
        this.properties = properties;
    }

    public DailyEnrichmentProviderReadiness check(LocalDate targetDate) {
        Map<String, ProbeInstrument> instruments = new LinkedHashMap<>();
        jdbcTemplate.query("""
                SELECT member.source_symbol, member.provider_instrument_key
                FROM universe_snapshot_member member
                JOIN universe_snapshot snapshot ON snapshot.id = member.snapshot_id
                WHERE snapshot.id = (
                    SELECT id FROM universe_snapshot
                    WHERE universe_code = 'NIFTY_500'
                    ORDER BY observed_on DESC, received_at DESC LIMIT 1
                )
                  AND member.match_status = 'MATCHED'
                ORDER BY member.source_symbol
                """, (rs, row) -> new ProbeInstrument(
                rs.getString("source_symbol"), rs.getString("provider_instrument_key")))
                .forEach(instrument -> instruments.put(
                        instrument.symbol().toUpperCase(Locale.ROOT), instrument));

        List<DailyEnrichmentProviderReadiness.Check> checks = new ArrayList<>();
        int available = 0;
        int missing = 0;
        int failed = 0;
        for (String configuredSymbol : properties.readinessSymbols()) {
            String symbol = configuredSymbol.trim().toUpperCase(Locale.ROOT);
            ProbeInstrument instrument = instruments.get(symbol);
            if (instrument == null) {
                checks.add(new DailyEnrichmentProviderReadiness.Check(symbol, "INSTRUMENT_NOT_MATCHED"));
                failed++;
                continue;
            }
            UpstoxFetchResult<List<UpstoxCandle>> result = upstoxClient.fetchIntradayCandles(
                    new UpstoxIntradayRequest(instrument.providerInstrumentKey(), "days", 1));
            if (!result.succeeded()) {
                checks.add(new DailyEnrichmentProviderReadiness.Check(symbol, result.status()));
                failed++;
                continue;
            }
            boolean targetPresent = result.data() != null && result.data().stream()
                    .filter(candle -> candle.openedAt() != null)
                    .anyMatch(candle -> candle.openedAt().atZone(INDIA).toLocalDate().equals(targetDate));
            checks.add(new DailyEnrichmentProviderReadiness.Check(
                    symbol, targetPresent ? "TARGET_DATE_AVAILABLE" : "TARGET_DATE_NOT_AVAILABLE"));
            if (targetPresent) {
                available++;
            } else {
                missing++;
            }
        }
        int requested = properties.readinessSymbols().size();
        String status = failed > 0 ? "PROVIDER_CHECK_FAILED"
                : available == requested ? "READY" : "WAITING_FOR_TARGET_DATE";
        String detail = switch (status) {
            case "READY" -> "All configured liquid-instrument probes contain the finalized target date.";
            case "WAITING_FOR_TARGET_DATE" -> "Upstox has not exposed the target date for every readiness probe.";
            default -> "One or more readiness probes could not be completed safely.";
        };
        return new DailyEnrichmentProviderReadiness(
                targetDate, status, requested, available, missing, failed, checks, false, detail);
    }

    private record ProbeInstrument(String symbol, String providerInstrumentKey) {
    }
}
