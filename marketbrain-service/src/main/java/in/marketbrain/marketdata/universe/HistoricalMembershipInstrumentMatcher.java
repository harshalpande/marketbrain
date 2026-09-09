package in.marketbrain.marketdata.universe;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Component
public class HistoricalMembershipInstrumentMatcher {

    private final JdbcTemplate jdbcTemplate;

    public HistoricalMembershipInstrumentMatcher(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public List<HistoricalMembershipInstrumentMatch> matchAll(
            List<Nifty500MembershipRecord> records,
            LocalDate asOf
    ) {
        List<HistoricalMembershipInstrumentMatch> matches = new ArrayList<>(records.size());
        for (Nifty500MembershipRecord record : records) {
            matches.add(match(record, asOf));
        }
        return List.copyOf(matches);
    }

    private HistoricalMembershipInstrumentMatch match(
            Nifty500MembershipRecord record,
            LocalDate asOf
    ) {
        List<MatchedInstrument> currentIsin = jdbcTemplate.query("""
                SELECT id, symbol
                FROM instrument
                WHERE exchange = 'NSE' AND UPPER(isin) = ?
                ORDER BY active DESC, id
                """, (rs, row) -> new MatchedInstrument(rs.getLong(1), rs.getString(2)), record.isin());
        if (currentIsin.size() == 1) {
            MatchedInstrument match = currentIsin.getFirst();
            return HistoricalMembershipInstrumentMatch.matched(
                    match.instrumentId(), match.currentSymbol(), "CURRENT_ISIN");
        }
        if (currentIsin.size() > 1) {
            return HistoricalMembershipInstrumentMatch.ambiguous("CURRENT_ISIN");
        }

        List<MatchedInstrument> historicalIsin = jdbcTemplate.query("""
                SELECT instrument.id, instrument.symbol
                FROM instrument_identity_alias alias
                JOIN instrument
                  ON instrument.exchange = alias.exchange
                 AND instrument.symbol = alias.current_symbol
                WHERE alias.exchange = 'NSE'
                  AND UPPER(alias.alias_isin) = ?
                  AND ? BETWEEN alias.effective_from AND alias.effective_to
                ORDER BY instrument.active DESC, instrument.id
                """, (rs, row) -> new MatchedInstrument(rs.getLong(1), rs.getString(2)),
                record.isin(), Date.valueOf(asOf));
        if (historicalIsin.size() == 1) {
            MatchedInstrument match = historicalIsin.getFirst();
            return HistoricalMembershipInstrumentMatch.matched(
                    match.instrumentId(), match.currentSymbol(), "HISTORICAL_ISIN");
        }
        if (historicalIsin.size() > 1) {
            return HistoricalMembershipInstrumentMatch.ambiguous("HISTORICAL_ISIN");
        }
        return HistoricalMembershipInstrumentMatch.unmatched();
    }

    private record MatchedInstrument(long instrumentId, String currentSymbol) {
    }
}
