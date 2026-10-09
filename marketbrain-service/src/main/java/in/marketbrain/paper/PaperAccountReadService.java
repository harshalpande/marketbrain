package in.marketbrain.paper;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Read-only bridge to V1 data. Never initializes an account or treats legacy cash as buying power. */
@Service
public class PaperAccountReadService {
    private final JdbcTemplate jdbc;

    public PaperAccountReadService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public record Account(String id, String name, String executionMode, String startingCash, String currentCash) {}
    public record Overview(String version, String status, String observedAtUtc, String currency,
                           Account account, int activeAccountsObserved, boolean activeAccountCountIsLowerBound,
                           boolean legacyOrdersPresent, boolean legacyFillsPresent, String migrationAssessment,
                           List<String> blockers, boolean databaseWritesPerformed, boolean actionExecutionEnabled,
                           boolean liveExecutionEnabled) {}

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ, timeout = 10)
    public Overview overview() {
        // LIMIT 2 intentionally detects ambiguity without unbounded counts. PK ordering avoids a sort.
        List<Account> accounts = jdbc.query("""
                SELECT id, name, execution_mode::text AS execution_mode, starting_cash, current_cash
                FROM paper_portfolio WHERE active = TRUE ORDER BY id LIMIT 2
                """, (rs, row) -> new Account(Long.toString(rs.getLong("id")), rs.getString("name"),
                rs.getString("execution_mode"), rs.getBigDecimal("starting_cash").toPlainString(),
                rs.getBigDecimal("current_cash").toPlainString()));
        // Global existence is deliberate: even inactive-account history requires migration review.
        boolean orders = !jdbc.query("SELECT id FROM paper_order ORDER BY id LIMIT 1",
                (rs, row) -> rs.getString("id")).isEmpty();
        boolean fills = !jdbc.query("SELECT id FROM paper_fill ORDER BY id LIMIT 1",
                (rs, row) -> rs.getString("id")).isEmpty();
        return assess(accounts, orders, fills, Instant.now());
    }

    static Overview assess(List<Account> accounts, boolean orders, boolean fills, Instant observed) {
        var blockers = new ArrayList<String>();
        Account account = accounts.size() == 1 ? accounts.getFirst() : null;
        if (accounts.isEmpty()) blockers.add("NO_ACTIVE_ACCOUNT_DO_NOT_RESEED");
        if (accounts.size() > 1) blockers.add("MULTIPLE_ACTIVE_ACCOUNTS_REVIEW_REQUIRED");
        if (account != null) {
            if (!"PAPER".equals(account.executionMode())) blockers.add("ACCOUNT_MODE_INVALID");
            if (!validMoney(account.startingCash()) || !validMoney(account.currentCash())) {
                blockers.add("ACCOUNT_CASH_INVALID");
            } else if (new BigDecimal(account.startingCash()).compareTo(new BigDecimal("100000")) != 0
                    || new BigDecimal(account.currentCash()).compareTo(new BigDecimal(account.startingCash())) != 0) {
                blockers.add("EXISTING_BALANCE_REQUIRES_RECONCILIATION");
            }
        }
        if (orders || fills) blockers.add("LEGACY_HISTORY_REQUIRES_MIGRATION_REVIEW");
        String assessment = blockers.isEmpty() ? "EMPTY_ACCOUNT_REVIEWABLE" : "REVIEW_REQUIRED";
        blockers.add("APPLICATION_LEDGER_MIGRATION_PENDING");
        blockers.add("AUTHENTICATED_APPROVAL_AND_RISK_INTEGRATION_PENDING");
        blockers.add("FILL_COST_AND_PNL_POLICY_PENDING");
        return new Overview("PAPER_ACCOUNT_OVERVIEW_V1", "READ_ONLY_EXECUTION_BLOCKED", observed.toString(), "INR",
                account, accounts.size(), accounts.size() >= 2, orders, fills, assessment, List.copyOf(blockers),
                false, false, false);
    }

    private static boolean validMoney(String text) {
        try {
            BigDecimal value = new BigDecimal(text);
            return value.signum() >= 0 && value.scale() <= 2 && value.precision() <= 18;
        } catch (RuntimeException invalid) { return false; }
    }
}
