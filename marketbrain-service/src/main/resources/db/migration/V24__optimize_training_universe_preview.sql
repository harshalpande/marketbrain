CREATE INDEX idx_instrument_active_nse_symbol
    ON instrument (symbol, id)
    WHERE exchange = 'NSE' AND active = TRUE;

CREATE INDEX idx_market_candle_daily_complete_preview
    ON market_candle (instrument_id, opened_at DESC, source_id, received_at DESC, id DESC)
    WHERE interval_code = 'days:1' AND is_complete = TRUE;

COMMENT ON INDEX idx_market_candle_daily_complete_preview IS
    'Speeds read-only fallback tradable-equity universe previews over governed daily candles.';
