package in.marketbrain.marketdata.upstox;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;

@Service
public class UpstoxMarketDataService {

    private static final String SOURCE_CODE = "UPSTOX";

    private final UpstoxReadOnlyClient client;
    private final UpstoxDataQualityService qualityService;
    private final UpstoxCandleBatchNormalizer candleBatchNormalizer;
    private final JdbcTemplate jdbcTemplate;

    public UpstoxMarketDataService(
            UpstoxReadOnlyClient client,
            UpstoxDataQualityService qualityService,
            UpstoxCandleBatchNormalizer candleBatchNormalizer,
            JdbcTemplate jdbcTemplate
    ) {
        this.client = client;
        this.qualityService = qualityService;
        this.candleBatchNormalizer = candleBatchNormalizer;
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public UpstoxImportResult importNseEquityInstruments() {
        UpstoxFetchResult<List<UpstoxInstrument>> fetch = client.fetchNseInstruments();
        if (!fetch.succeeded()) {
            markSourceFailureUnlessDisabled(fetch);
            return UpstoxImportResult.providerFailure(fetch);
        }

        List<UpstoxInstrument> accepted = fetch.data().stream().filter(UpstoxInstrument::isNseEquity).toList();
        if (accepted.isEmpty()) {
            markSourceFailure();
            return new UpstoxImportResult(
                    "INVALID_DATA", fetch.data().size(), 0, fetch.data().size(), 0, List.of(), List.of(),
                    "The provider file contained no valid NSE cash-equity instruments.");
        }
        jdbcTemplate.update("""
                UPDATE provider_instrument mapping
                SET active = FALSE
                FROM market_data_source source
                WHERE mapping.source_id = source.id AND source.code = ?
                """, SOURCE_CODE);
        for (UpstoxInstrument item : accepted) {
            jdbcTemplate.update("""
                    INSERT INTO instrument (exchange, symbol, isin, display_name, active)
                    VALUES ('NSE', ?, ?, ?, TRUE)
                    ON CONFLICT (exchange, symbol) DO UPDATE SET
                        isin = EXCLUDED.isin,
                        display_name = EXCLUDED.display_name,
                        active = TRUE,
                        updated_at = CURRENT_TIMESTAMP
                    """, item.tradingSymbol(), item.isin(), item.name());
            jdbcTemplate.update("""
                    INSERT INTO provider_instrument
                        (source_id, instrument_id, provider_instrument_key, segment, instrument_type, active)
                    SELECT source.id, instrument.id, ?, ?, ?, TRUE
                    FROM market_data_source source
                    JOIN instrument ON instrument.exchange = 'NSE' AND instrument.symbol = ?
                    WHERE source.code = ?
                    ON CONFLICT (source_id, provider_instrument_key) DO UPDATE SET
                        instrument_id = EXCLUDED.instrument_id,
                        segment = EXCLUDED.segment,
                        instrument_type = EXCLUDED.instrument_type,
                        active = TRUE,
                        received_at = CURRENT_TIMESTAMP
                    """, item.instrumentKey(), item.segment(), item.instrumentType(),
                    item.tradingSymbol(), SOURCE_CODE);
        }
        markSourceSuccess();
        return new UpstoxImportResult("SUCCESS", fetch.data().size(), accepted.size(),
                fetch.data().size() - accepted.size(), 0, List.of(), List.of(),
                "Official Upstox NSE instrument file imported; only NSE cash equities were accepted.");
    }

    @Transactional
    public UpstoxQuoteResult fetchAndStoreQuote(String instrumentKey) {
        UpstoxFetchResult<UpstoxQuote> fetch = client.fetchFullQuote(instrumentKey);
        if (!fetch.succeeded()) {
            markSourceFailureUnlessDisabled(fetch);
            return UpstoxQuoteResult.providerFailure(instrumentKey, fetch);
        }

        UpstoxQuote quote = fetch.data();
        MarketDataQuality quality = qualityService.assess(quote);
        if ("INVALID".equals(quality.status())) {
            markSourceFailure();
            return new UpstoxQuoteResult("INVALID_DATA", quote.instrumentKey(), quote.tradingSymbol(),
                    quote.lastPrice(), quote.providerPublishedAt(), quote.lastTradeAt(), quality.status(),
                    quality.ageSeconds(), false, false, quality.detail());
        }

        Long instrumentId = findInstrumentId(instrumentKey);
        boolean persisted = instrumentId != null;
        if (persisted) {
            Instant publishedAt = quote.providerPublishedAt() != null
                    ? quote.providerPublishedAt() : quote.lastTradeAt();
            jdbcTemplate.update("""
                    INSERT INTO market_quote_snapshot
                        (instrument_id, source_id, provider_instrument_key, provider_published_at,
                         last_trade_at, last_price, previous_close, volume, quality_status)
                    SELECT ?, id, ?, ?, ?, ?, ?, ?, ?
                    FROM market_data_source WHERE code = ?
                    ON CONFLICT (source_id, provider_instrument_key, provider_published_at) DO UPDATE SET
                        last_trade_at = EXCLUDED.last_trade_at,
                        received_at = CURRENT_TIMESTAMP,
                        last_price = EXCLUDED.last_price,
                        previous_close = EXCLUDED.previous_close,
                        volume = EXCLUDED.volume,
                        quality_status = EXCLUDED.quality_status
                    """, instrumentId, instrumentKey, Timestamp.from(publishedAt), timestampOrNull(quote.lastTradeAt()),
                    quote.lastPrice(), quote.previousClose(), quote.volume(), quality.status(), SOURCE_CODE);
        }
        markSourceSuccess();
        String detail = persisted ? quality.detail()
                : quality.detail() + " Import the NSE instrument master before persisting this key.";
        return new UpstoxQuoteResult("SUCCESS", quote.instrumentKey(), quote.tradingSymbol(), quote.lastPrice(),
                quote.providerPublishedAt(), quote.lastTradeAt(), quality.status(), quality.ageSeconds(),
                quality.isUsableForAction(), persisted, detail);
    }

    @Transactional
    public UpstoxImportResult importHistoricalCandles(UpstoxHistoricalRequest request) {
        UpstoxFetchResult<List<UpstoxCandle>> fetch = client.fetchHistoricalCandles(request);
        if (!fetch.succeeded()) {
            markSourceFailureUnlessDisabled(fetch);
            return UpstoxImportResult.providerFailure(fetch);
        }
        Long instrumentId = findInstrumentId(request.instrumentKey());
        if (instrumentId == null) {
            return new UpstoxImportResult("INSTRUMENT_NOT_IMPORTED", fetch.data().size(), 0,
                    fetch.data().size(), 0, List.of(), List.of(),
                    "Import the NSE instrument master before candle ingestion.");
        }

        List<UpstoxCandle> validCandles = fetch.data().stream().filter(qualityService::validCandle).toList();
        UpstoxCandleBatchNormalizer.Result normalized = candleBatchNormalizer.normalize(request, validCandles);
        if (normalized.hasConflicts()) {
            markSourceFailure();
            return new UpstoxImportResult(
                    "INVALID_DATA", fetch.data().size(), 0, fetch.data().size(), 0, List.of(), List.of(),
                    "Upstox returned different daily OHLCV values for the same trading date(s): "
                            + normalized.conflictingTradingDates() + ". Nothing from this response was persisted.");
        }

        for (UpstoxCandleBatchNormalizer.NormalizedCandle normalizedCandle : normalized.candles()) {
            UpstoxCandle candle = normalizedCandle.candle();
            int persistedRows = jdbcTemplate.update("""
                    INSERT INTO market_candle
                        (instrument_id, source_id, interval_code, opened_at, provider_opened_at, source_published_at,
                         open_price, high_price, low_price, close_price, volume, is_complete)
                    SELECT ?, id, ?, ?, ?, NULL, ?, ?, ?, ?, ?, TRUE
                    FROM market_data_source WHERE code = ?
                    ON CONFLICT (instrument_id, source_id, interval_code, opened_at) DO UPDATE SET
                        provider_opened_at = EXCLUDED.provider_opened_at,
                        source_published_at = EXCLUDED.source_published_at,
                        received_at = CURRENT_TIMESTAMP,
                        open_price = EXCLUDED.open_price,
                        high_price = EXCLUDED.high_price,
                        low_price = EXCLUDED.low_price,
                        close_price = EXCLUDED.close_price,
                        volume = EXCLUDED.volume,
                        is_complete = TRUE
                    WHERE market_candle.open_price = EXCLUDED.open_price
                      AND market_candle.high_price = EXCLUDED.high_price
                      AND market_candle.low_price = EXCLUDED.low_price
                      AND market_candle.close_price = EXCLUDED.close_price
                      AND market_candle.volume IS NOT DISTINCT FROM EXCLUDED.volume
                    """, instrumentId, request.intervalCode(), Timestamp.from(candle.openedAt()),
                    Timestamp.from(normalizedCandle.providerOpenedAt()),
                    candle.open(), candle.high(), candle.low(), candle.close(), candle.volume(), SOURCE_CODE);
            if (persistedRows == 0) {
                throw new ConflictingCandleDataException(
                        "Upstox returned OHLCV values that conflict with the stored candle for "
                                + candle.openedAt() + ". Nothing from this response was persisted.");
            }
        }
        markSourceSuccess();
        int invalidRows = fetch.data().size() - validCandles.size();
        return new UpstoxImportResult("SUCCESS", fetch.data().size(), normalized.candles().size(), invalidRows,
                normalized.collapsedDuplicates(), normalized.normalizedTradingDates(),
                normalized.normalizationDetails(),
                "Historical candles passed OHLC, timestamp, and volume validation; "
                        + normalized.collapsedDuplicates() + " near-identical same-date row(s) were normalized.");
    }

    private Long findInstrumentId(String instrumentKey) {
        List<Long> ids = jdbcTemplate.query("""
                SELECT mapping.instrument_id
                FROM provider_instrument mapping
                JOIN market_data_source source ON source.id = mapping.source_id
                WHERE source.code = ? AND mapping.provider_instrument_key = ? AND mapping.active = TRUE
                """, (resultSet, rowNumber) -> resultSet.getLong(1), SOURCE_CODE, instrumentKey);
        return ids.isEmpty() ? null : ids.getFirst();
    }

    private void markSourceSuccess() {
        jdbcTemplate.update("""
                UPDATE market_data_source
                SET enabled = TRUE, status = 'AVAILABLE', last_success_at = CURRENT_TIMESTAMP
                WHERE code = ?
                """, SOURCE_CODE);
    }

    private void markSourceFailure() {
        jdbcTemplate.update("""
                UPDATE market_data_source
                SET status = 'FAILED', last_failure_at = CURRENT_TIMESTAMP
                WHERE code = ?
                """, SOURCE_CODE);
    }

    private void markSourceFailureUnlessDisabled(UpstoxFetchResult<?> fetch) {
        if (!"NOT_CONFIGURED".equals(fetch.status())) {
            markSourceFailure();
        }
    }

    private Timestamp timestampOrNull(Instant value) {
        return value == null ? null : Timestamp.from(value);
    }
}
