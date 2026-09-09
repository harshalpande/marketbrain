package in.marketbrain.marketdata.universe;

public record HistoricalMembershipInstrumentMatch(
        String matchStatus,
        Long instrumentId,
        String currentSymbol,
        String matchBasis
) {
    public static HistoricalMembershipInstrumentMatch matched(
            long instrumentId,
            String currentSymbol,
            String matchBasis
    ) {
        return new HistoricalMembershipInstrumentMatch(
                "MATCHED", instrumentId, currentSymbol, matchBasis);
    }

    public static HistoricalMembershipInstrumentMatch unmatched() {
        return new HistoricalMembershipInstrumentMatch(
                "UNMATCHED", null, null, "NONE");
    }

    public static HistoricalMembershipInstrumentMatch ambiguous(String basis) {
        return new HistoricalMembershipInstrumentMatch(
                "AMBIGUOUS", null, null, basis);
    }
}
