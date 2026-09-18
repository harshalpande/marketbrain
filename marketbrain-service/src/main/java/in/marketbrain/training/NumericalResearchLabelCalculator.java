package in.marketbrain.training;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/** Pure research arithmetic. Caller supplies a verified session calendar and canonical tradable prices.
 * Does not certify those inputs, infer availability, persist labels, fit a model or place orders. */
public final class NumericalResearchLabelCalculator {
    public enum Status { LABELED_RESEARCH_ONLY, CALENDAR_HORIZON_UNAVAILABLE, MISSING_BAR, INVALID_BAR, NON_EXECUTABLE_BAR }
    public record Bar(LocalDate session, BigDecimal open, BigDecimal high, BigDecimal low,
                      BigDecimal close, boolean executable) { }
    public record Result(String version, Status status, LocalDate decisionDate, LocalDate entryDate,
                         LocalDate exitDate, LocalDate problemDate, String calendarVersion,
                         String pricePolicyVersion, String costPolicyVersion, BigDecimal costBps,
                         BigDecimal entryOpen, BigDecimal exitClose, BigDecimal grossReturnPercent,
                         BigDecimal assumedCostPercent, BigDecimal netReturnPercent,
                         boolean trainingAuthorized) { }

    public Result calculate(LocalDate decisionDate, List<LocalDate> calendar, Map<LocalDate, Bar> bars,
                            String calendarVersion, String pricePolicyVersion,
                            String costPolicyVersion, BigDecimal roundTripCostBps) {
        Objects.requireNonNull(decisionDate, "decisionDate");
        Objects.requireNonNull(calendar, "calendar");
        Objects.requireNonNull(bars, "bars");
        for (String version : new String[]{calendarVersion,pricePolicyVersion,costPolicyVersion}) {
            if (version == null || version.isBlank()) { throw new IllegalArgumentException("Explicit policy versions required."); }
        }
        if (roundTripCostBps == null || roundTripCostBps.signum() < 0 || roundTripCostBps.compareTo(new BigDecimal("10000")) > 0) {
            throw new IllegalArgumentException("Explicit round-trip cost must be 0..10000 basis points.");
        }
        LocalDate previous = null;
        for (LocalDate session : calendar) {
            if (session == null || previous != null && !session.isAfter(previous)) {
                throw new IllegalArgumentException("Calendar must have unique ascending sessions.");
            }
            previous = session;
        }
        int decision = calendar.indexOf(decisionDate);
        if (decision < 0) { throw new IllegalArgumentException("Decision must be a declared exchange session."); }
        LocalDate entry = decision+1 < calendar.size() ? calendar.get(decision+1) : null;
        LocalDate exit = decision+20 < calendar.size() ? calendar.get(decision+20) : null;
        Status status = exit == null ? Status.CALENDAR_HORIZON_UNAVAILABLE : Status.LABELED_RESEARCH_ONLY;
        LocalDate problem = null;
        if (exit != null) {
            // Require the complete path; no silently skipping a suspension/missing session.
            for (int i=decision+1; i<=decision+20; i++) {
                LocalDate date=calendar.get(i);
                Bar bar=bars.get(date);
                if (bar == null) { status=Status.MISSING_BAR; }
                else if (!date.equals(bar.session()) || !valid(bar)) { status=Status.INVALID_BAR; }
                else if (!bar.executable()) { status=Status.NON_EXECUTABLE_BAR; }
                if (status != Status.LABELED_RESEARCH_ONLY) { problem=date;break; }
            }
        }
        BigDecimal entryOpen=null,exitClose=null,gross=null,cost=null,net=null;
        if (status == Status.LABELED_RESEARCH_ONLY) {
            entryOpen=bars.get(entry).open();exitClose=bars.get(exit).close();
            gross=exitClose.divide(entryOpen,16,RoundingMode.HALF_UP).subtract(BigDecimal.ONE)
                    .multiply(new BigDecimal("100")).setScale(8,RoundingMode.HALF_UP);
            cost=roundTripCostBps.divide(new BigDecimal("100"),8,RoundingMode.HALF_UP);
            net=gross.subtract(cost);
        }
        return new Result("NUMERICAL_RESEARCH_LABEL_20_V1",status,decisionDate,entry,exit,problem,
                calendarVersion,pricePolicyVersion,costPolicyVersion,roundTripCostBps,
                entryOpen,exitClose,gross,cost,net,false);
    }

    private boolean valid(Bar bar) {
        for (BigDecimal value : new BigDecimal[]{bar.open(),bar.high(),bar.low(),bar.close()}) {
            if (value == null || value.signum() <= 0) { return false; }
        }
        return bar.low().compareTo(bar.open())<=0 && bar.low().compareTo(bar.close())<=0
                && bar.high().compareTo(bar.open())>=0 && bar.high().compareTo(bar.close())>=0;
    }
}
